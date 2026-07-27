namespace :takedown do
  desc "Hide a user and remove their repositories. LOGIN=username [HOST=GitHub]"
  task hide_user: :environment do
    login = ENV['LOGIN']
    host_name = ENV['HOST'] || 'GitHub'
    abort "LOGIN is required" if login.blank?

    host = Host.find_by_name(host_name)
    abort "Host #{host_name} not found" if host.nil?

    owner = host.owners.find_by('lower(login) = ?', login.downcase)
    owner ||= host.owners.create!(login: login)
    owner.update!(hidden: true)
    puts "[commits] hidden owner #{host.name}/#{owner.login}"

    committers = host.committers.where('lower(login) = ?', login.downcase)
    committers.each do |c|
      c.update!(hidden: true)
      puts "[commits] hidden committer #{host.name}/#{c.login}"
    end

    repos = host.repositories.where('lower(owner) = ?', login.downcase)
    count = repos.count
    repos.find_each do |repo|
      puts "[commits] destroying #{repo.full_name}"
      repo.destroy
    end
    puts "[commits] destroyed #{count} repositories for #{host.name}/#{login}"
  end

  desc "Hide a committer by email and scrub existing data. EMAIL=addr [HOST=GitHub]"
  task hide_committer: :environment do
    email = ENV['EMAIL']
    host_name = ENV['HOST'] || 'GitHub'
    abort "EMAIL is required" if email.blank?

    host = Host.find_by_name(host_name)
    abort "Host #{host_name} not found" if host.nil?

    committer = host.committers.email(email).first
    committer ||= host.committers.create!(emails: [email])
    committer.update!(hidden: true)
    puts "[commits] hidden committer #{host.name}/#{email}"

    repo_count = 0
    host.repositories.committer_email(email).find_each do |repo|
      Contribution.find_or_create_by!(repository_id: repo.id, committer_id: committer.id)
      repo.update_columns(
        committers: repo.redact_committers(repo.committers || []),
        past_year_committers: repo.redact_committers(repo.past_year_committers || [])
      )
      redacted = repo.commits.where("author LIKE ? OR committer LIKE ?", "%<#{email}>%", "%<#{email}>%")
                     .update_all(author: 'redacted <redacted>', committer: 'redacted <redacted>')
      puts "[commits] scrubbed #{repo.full_name} (#{redacted} commit rows)"
      repo_count += 1
    end
    puts "[commits] scrubbed #{repo_count} repositories for #{host.name}/#{email}"
  end

  desc "Report what exists for a user. LOGIN=username [HOST=GitHub]"
  task report: :environment do
    login = ENV['LOGIN']
    host_name = ENV['HOST'] || 'GitHub'
    abort "LOGIN is required" if login.blank?

    host = Host.find_by_name(host_name)
    abort "Host #{host_name} not found" if host.nil?

    owner = host.owners.find_by('lower(login) = ?', login.downcase)
    committer = host.committers.find_by('lower(login) = ?', login.downcase)
    repo_count = host.repositories.where('lower(owner) = ?', login.downcase).count
    puts "[commits] #{host.name}/#{login}: owner=#{owner ? (owner.hidden? ? 'hidden' : 'visible') : 'none'} committer=#{committer ? (committer.hidden? ? 'hidden' : 'visible') : 'none'} repositories=#{repo_count}"
  end
end
