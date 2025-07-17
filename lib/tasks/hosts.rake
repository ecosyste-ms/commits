namespace :hosts do
  desc 'update counts'
  task update_counts: :environment do
    Host.all.each(&:update_counts)
  end

  desc 'sync all'
  task sync_all: :environment do
    Host.sync_all
  end

  desc 'identify duplicate hosts with different cases'
  task identify_duplicates: :environment do
    duplicates = Host.all.group_by(&:name).transform_values(&:count).select { |_, count| count > 1 }
    case_duplicates = {}
    
    Host.all.each do |host|
      downcase_name = host.name.downcase
      case_duplicates[downcase_name] ||= []
      case_duplicates[downcase_name] << host
    end
    
    case_duplicates.select! { |_, hosts| hosts.size > 1 }
    
    puts "Found #{case_duplicates.size} host names with case variations:"
    case_duplicates.each do |downcase_name, hosts|
      puts "  #{downcase_name}:"
      hosts.each do |host|
        puts "    - #{host.name} (ID: #{host.id}, repos: #{host.repositories_count}, commits: #{host.commits_count})"
      end
    end
  end

  desc 'merge repositories and commits to downcased hosts'
  task merge_duplicates: :environment do
    case_duplicates = {}
    
    Host.all.each do |host|
      downcase_name = host.name.downcase
      case_duplicates[downcase_name] ||= []
      case_duplicates[downcase_name] << host
    end
    
    case_duplicates.select! { |_, hosts| hosts.size > 1 }
    
    case_duplicates.each do |downcase_name, hosts|
      # Find or create the target host (downcased)
      target_host = hosts.find { |h| h.name == downcase_name }
      unless target_host
        # Create a new host with the downcased name
        first_host = hosts.first
        target_host = Host.create!(
          name: downcase_name,
          url: first_host.url,
          kind: first_host.kind,
          icon_url: first_host.icon_url,
          last_synced_at: first_host.last_synced_at
        )
        puts "Created new target host: #{target_host.name}"
      end
      
      # Merge data from all other hosts to the target
      hosts.each do |host|
        next if host == target_host
        
        puts "Merging #{host.name} (ID: #{host.id}) into #{target_host.name} (ID: #{target_host.id})"
        
        # Move repositories (handle duplicates by merging)
        host.repositories.each do |repo|
          begin
            # Check if target host already has this repository
            existing_repo = target_host.repositories.find_by('lower(full_name) = ?', repo.full_name.downcase)
            
            if existing_repo
              puts "  Merging duplicate repository: #{repo.full_name}"
              # Merge data from repo into existing_repo
              existing_repo.update!(
                description: existing_repo.description.blank? ? repo.description : existing_repo.description,
                language: existing_repo.language.blank? ? repo.language : existing_repo.language,
                homepage: existing_repo.homepage.blank? ? repo.homepage : existing_repo.homepage,
                topics: existing_repo.topics.blank? ? repo.topics : existing_repo.topics,
                fork: existing_repo.fork || repo.fork,
                archived: existing_repo.archived || repo.archived,
                pushed_at: [existing_repo.pushed_at, repo.pushed_at].compact.max,
                last_synced_at: [existing_repo.last_synced_at, repo.last_synced_at].compact.max,
                total_commits: [existing_repo.total_commits || 0, repo.total_commits || 0].max,
                total_committers: [existing_repo.total_committers || 0, repo.total_committers || 0].max,
                stargazers_count: [existing_repo.stargazers_count || 0, repo.stargazers_count || 0].max,
                watchers_count: [existing_repo.watchers_count || 0, repo.watchers_count || 0].max,
                forks_count: [existing_repo.forks_count || 0, repo.forks_count || 0].max,
                open_issues_count: [existing_repo.open_issues_count || 0, repo.open_issues_count || 0].max,
                size: [existing_repo.size || 0, repo.size || 0].max
              )
              
              # Move commits from repo to existing_repo (handle duplicate SHAs)
              commits_count = repo.commits.count
              repo.commits.find_each do |commit|
                # Check if existing_repo already has this commit SHA
                existing_commit = existing_repo.commits.find_by(sha: commit.sha)
                if existing_commit
                  # Duplicate commit, just delete it
                  commit.destroy
                else
                  # Move the commit
                  commit.update!(repository: existing_repo)
                end
              end
              puts "    Processed #{commits_count} commits for existing repository"
              
              # Move contributions from repo to existing_repo
              contributions_count = repo.contributions.count
              repo.contributions.update_all(repository_id: existing_repo.id)
              puts "    Moved #{contributions_count} contributions to existing repository"
              
              # Delete the duplicate repository
              repo.destroy
              puts "    Deleted duplicate repository: #{repo.full_name}"
            else
              # No duplicate, just move the repository
              repo.update!(host: target_host)
              puts "  Moved repository: #{repo.full_name}"
            end
          rescue => e
            puts "  Error processing repository #{repo.full_name}: #{e.message}"
          end
        end
        
        # Move committers (handle duplicates by merging)
        host.committers.each do |committer|
          begin
            # Check if target host already has this committer (by login or email)
            existing_committer = nil
            if committer.login.present?
              existing_committer = target_host.committers.find_by(login: committer.login)
            end
            
            if existing_committer.nil? && committer.emails.present?
              # Check by email if no login match
              existing_committer = target_host.committers.find { |c| (c.emails & committer.emails).any? }
            end
            
            if existing_committer
              puts "  Merging duplicate committer: #{committer.login || committer.emails.first}"
              # Merge emails
              merged_emails = (existing_committer.emails + committer.emails).uniq.compact
              existing_committer.update!(emails: merged_emails)
              
              # Merge login (prefer non-nil)
              if existing_committer.login.blank? && committer.login.present?
                existing_committer.update!(login: committer.login)
              end
              
              # Move contributions from committer to existing_committer
              committer.contributions.each do |contribution|
                # Check if existing_committer already has a contribution to this repository
                existing_contribution = existing_committer.contributions.find_by(repository: contribution.repository)
                if existing_contribution
                  # Merge commit counts
                  existing_contribution.update!(commit_count: existing_contribution.commit_count + contribution.commit_count)
                  contribution.destroy
                  puts "    Merged contribution to #{contribution.repository.full_name}"
                else
                  # Move the contribution
                  contribution.update!(committer: existing_committer)
                  puts "    Moved contribution to #{contribution.repository.full_name}"
                end
              end
              
              # Update commits count
              existing_committer.update_commits_count
              
              # Delete the duplicate committer
              committer.destroy
              puts "    Deleted duplicate committer: #{committer.login || committer.emails.first}"
            else
              # No duplicate, just move the committer
              committer.update!(host: target_host)
              puts "  Moved committer: #{committer.login || committer.emails.first}"
            end
          rescue => e
            puts "  Error processing committer #{committer.login || committer.emails.first}: #{e.message}"
          end
        end
      end
      
      # Update counts for the target host
      target_host.update_counts
      puts "Updated counts for #{target_host.name}: repos=#{target_host.repositories_count}, commits=#{target_host.commits_count}"
    end
  end

  desc 'remove empty duplicate hosts after merge'
  task remove_duplicates: :environment do
    case_duplicates = {}
    
    Host.all.each do |host|
      downcase_name = host.name.downcase
      case_duplicates[downcase_name] ||= []
      case_duplicates[downcase_name] << host
    end
    
    case_duplicates.select! { |_, hosts| hosts.size > 1 }
    
    case_duplicates.each do |downcase_name, hosts|
      target_host = hosts.find { |h| h.name == downcase_name }
      
      hosts.each do |host|
        next if host == target_host
        
        # Only remove if empty
        if host.repositories.count == 0 && host.committers.count == 0
          puts "Removing empty host: #{host.name} (ID: #{host.id})"
          host.destroy
        else
          puts "Skipping non-empty host: #{host.name} (repos: #{host.repositories.count}, committers: #{host.committers.count})"
        end
      end
    end
  end

  desc 'force cleanup any remaining duplicates'
  task force_cleanup: :environment do
    case_duplicates = {}
    
    Host.all.each do |host|
      downcase_name = host.name.downcase
      case_duplicates[downcase_name] ||= []
      case_duplicates[downcase_name] << host
    end
    
    case_duplicates.select! { |_, hosts| hosts.size > 1 }
    
    case_duplicates.each do |downcase_name, hosts|
      target_host = hosts.find { |h| h.name == downcase_name }
      
      hosts.each do |host|
        next if host == target_host
        
        puts "Force removing host: #{host.name} (ID: #{host.id})"
        host.destroy
      end
    end
  end
end