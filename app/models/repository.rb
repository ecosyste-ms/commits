class Repository < ApplicationRecord
  belongs_to :host

  has_many :commits

  validates :full_name, presence: true

  scope :active, -> { where(status: nil) }
  scope :visible, -> { active.where.not(last_synced_at: nil).where.not(total_commits: nil) }
  scope :created_after, ->(date) { where('created_at > ?', date) }
  scope :updated_after, ->(date) { where('updated_at > ?', date) }

  def self.sync_least_recently_synced
    Repository.active.order('last_synced_at ASC').limit(1000).each(&:sync_async)
  end

  def to_s
    full_name
  end

  def to_param
    full_name
  end

  def subgroups
    return [] if full_name.split('/').size < 3
    full_name.split('/')[1..-2]
  end

  def project_slug
    full_name.split('/').last
  end

  def project_name
    full_name.split('/')[1..-1].join('/')
  end

  def owner
    full_name.split('/').first
  end

  def sync_async(remote_ip = '0.0.0.0')
    job = Job.new(url: html_url, status: 'pending', ip: remote_ip)
    if job.save
      job.parse_commits_async
    end
  end

  def sync_details
    conn = Faraday.new(repos_api_url) do |f|
      f.request :json
      f.request :retry
      f.response :json
    end
    response = conn.get
    if response.status == 404
      self.status = 'not_found'
      self.save
      return
    end
    return if response.status != 200
    json = response.body

    self.status = json['status']
    self.default_branch = json['default_branch']
    self.save    
  end

  def repos_url
    "https://repos.ecosyste.ms/hosts/#{host.name}/repositories/#{full_name}"
  end

  def repos_api_url
    "https://repos.ecosyste.ms/api/v1/hosts/#{host.name}/repositories/#{full_name}"
  end

  def folder_name
    full_name.split('/').last
  end

  def html_url
    "#{host.url}/#{full_name}"
  end

  def git_clone_url
    "#{host.url}/#{full_name}.git"
  end

  def fetch_head_sha
    `git ls-remote #{git_clone_url} #{default_branch}`.split("\t").first
  end

  # TODO support hg and svn repos

  def count_commits
    sync_details
    return if status == 'not_found'
    last_commit = fetch_head_sha

    if !past_year_committers.nil? && last_synced_commit == last_commit
      update(last_synced_at: Time.now)
    else
      begin
      Dir.mktmpdir do |dir|
        Rugged::Repository.clone_at(git_clone_url, dir)
        last_commit = `git -C #{dir} rev-parse HEAD`.strip
        output = `git -C #{dir} shortlog -s -n -e --no-merges HEAD`      

        past_year_output = `git -C #{dir} shortlog -s -n -e --no-merges --since="1 year ago" HEAD`

        committers = parse_commit_counts(output)

        past_year_committers = parse_commit_counts(past_year_output)

        total_commits = committers.sum{|h| h[:count]}
        total_bot_commits = committers.select{|h| h[:name].ends_with?('[bot]')}.sum{|h| h[:count]}

        past_year_total_commits = past_year_committers.sum{|h| h[:count]}
        past_year_total_bot_commits = past_year_committers.select{|h| h[:name].ends_with?('[bot]')}.sum{|h| h[:count]}

        if past_year_committers.first
          past_year_dds = 1 - (past_year_committers.first[:count].to_f / past_year_total_commits)
          past_year_mean_commits = (past_year_total_commits.to_f / past_year_committers.length)
        else
          past_year_dds = 0
          past_year_mean_commits = 0
        end

        updates = {
          committers: committers,
          last_synced_commit: last_commit,
          total_commits: total_commits,
          total_committers: committers.length,
          total_bot_commits: total_bot_commits,
          total_bot_committers: committers.select{|h| h[:name].ends_with?('[bot]')}.length,
          mean_commits: (total_commits.to_f / committers.length),
          dds: 1 - (committers.first[:count].to_f / total_commits),
          past_year_committers: past_year_committers,
          past_year_total_commits: past_year_total_commits,
          past_year_total_committers: past_year_committers.length,
          past_year_total_bot_commits: past_year_total_bot_commits,
          past_year_total_bot_committers: past_year_committers.select{|h| h[:name].ends_with?('[bot]')}.length,
          past_year_mean_commits: past_year_mean_commits,
          past_year_dds: past_year_dds,
          last_synced_at: Time.now
        }
        update(updates)
      end
      rescue
        # TODO record error in clone (likely missing repo but also maybe host downtime)
      end
    end
    
  end

  def parse_commit_counts(output)
    # parse the output of the git command
    # return an array of hashes with the author and commit count
    lines = output.split("\n").map do |line|
      count, author = line.split("\t")
      name, email = author.split("<")
      email.gsub!(/[<>]/, '')
      login = fetch_existing_login(email)
      { name: name.strip, email: email, login: login, count: count.to_i }
    end

    c = lines.group_by{|h| h[:email]}.map do |email, lines|
      { name: lines.first[:name], email: email, login: lines.first[:login], count: lines.sum{|h| h[:count]} }
    end.sort_by{|h| h[:count]}.reverse

    c_with_login = c.select{|h| h[:login].present? }
    c_without_login = c.select{|h| h[:login].blank? }
    grouped_logins = c_with_login.group_by{|h| h[:login]}.map do |login, lines|
      { name: lines.first[:name], email: lines.first[:email], login: login, count: lines.sum{|h| h[:count]} }
    end
    (grouped_logins + c_without_login).sort_by{|h| h[:count]}.reverse
  end

  def group_commits_by_login
    return unless committers
    updated_committers_with_login = committers.select{|h| h['login'].present? }.group_by{|h| h["login"]}.map do |login, lines|
      { 'name' => lines.first["name"], 'email' => lines.first['email'], 'login' => login, 'count' => lines.sum{|h| h["count"]} }
    end

    updated_committers = (committers.select{|h| h['login'].blank? } + updated_committers_with_login).sort_by{|h| h['count']}.reverse

    updates = {
      committers: updated_committers,
      total_committers: updated_committers.length,
      total_bot_committers: updated_committers.select{|h| h['name'].ends_with?('[bot]')}.length,
      total_bot_commits: updated_committers.select{|h| h['name'].ends_with?('[bot]')}.sum{|h| h['count']},
      mean_commits: (total_commits.to_f / updated_committers.length),
      dds: 1 - (updated_committers.first['count'].to_f / total_commits),
    }

    if past_year_committers && past_year_committers.length > 0
      updated_past_year_committers_with_login = past_year_committers.select{|h| h['login'].present? }.group_by{|h| h["login"]}.map do |login, lines|
        { 'name' => lines.first["name"], 'email' => lines.first['email'], 'login' => login, 'count' => lines.sum{|h| h["count"]} }
      end
  
      updated_past_year_committers = (past_year_committers.select{|h| h['login'].blank? } + updated_past_year_committers_with_login).sort_by{|h| h['count']}.reverse

      updates[:past_year_committers] = updated_past_year_committers
      updates[:past_year_total_committers] = updated_past_year_committers.length
      updates[:past_year_total_bot_committers] = updated_past_year_committers.select{|h| h['name'].ends_with?('[bot]')}.length
      updates[:past_year_total_bot_commits] = updated_past_year_committers.select{|h| h['name'].ends_with?('[bot]')}.sum{|h| h['count']}
      updates[:past_year_mean_commits] = (past_year_total_commits.to_f / updated_past_year_committers.length)
      updates[:past_year_dds] = 1 - (updated_past_year_committers.first['count'].to_f / past_year_total_commits)
    end

    update(updates)
  end

  def fetch_login(email)
    return nil if host.name != 'GitHub'

    return if REDIS.sismember('github_emails_nil', email)

    if email.include?('@users.noreply.github.com')
      login = email.gsub!('@users.noreply.github.com', '').split('+').last
      return login
    end

    existing_login = host.committers.email(email).first.try(:login)
    return existing_login if existing_login
    # TODO should be host agnostic
    commit = api_client.list_commits(full_name, author: email, per_page: 1).first
    return nil if commit.nil?
    login = commit.author.try(:login)
    REDIS.sadd('github_emails_nil', email) if login.nil?
    return nil if login.nil?
    # find committer by login and add email to committer
    committer = host.committers.find_by(login: login)
    if committer
      committer.emails << email
      committer.save
    else
      committer = host.committers.create(login: login, emails: [email])
    end
    committer.login
  rescue => e
    puts e
    nil
  end

  def fetch_all_logins
    return nil if host.name != 'GitHub'
    return if status == 'not_found'
    return if committers.nil?

    committers.each do |committer|
      next if committer['login'].present?
      committer['login'] = fetch_login(committer['email'])
    end

    if past_year_committers
      past_year_committers.each do |committer|
        next if committer['login'].present?
        committer['login'] = fetch_login(committer['email'])
      end
    end

    update(committers: committers, past_year_committers: past_year_committers)

    group_commits_by_login
  end

  def fetch_existing_login(email)
    return nil if host.name != 'GitHub'

    return nil if REDIS.sismember('github_emails_nil', email)

    if email.include?('@users.noreply.github.com')
      login = email.gsub!('@users.noreply.github.com', '').split('+').last
      return login
    end

    existing_login = host.committers.email(email).first.try(:login)
    return existing_login if existing_login
    nil
  end

  def fetch_all_existing_logins
    return nil if host.name != 'GitHub'
    return if committers.nil?

    committers.each do |committer|
      next if committer['login'].present?
      committer['login'] = fetch_existing_login(committer['email'])
    end

    if past_year_committers
      past_year_committers.each do |committer|
        next if committer['login'].present?
        committer['login'] = fetch_existing_login(committer['email'])
      end
    end

    update(committers: committers, past_year_committers: past_year_committers)

    group_commits_by_login
  end


  def committer_url(login)
    "#{host.url}/#{login}"
  end

  def token_set_key
    "github_tokens"
  end

  def list_tokens
    REDIS.smembers(token_set_key)
  end

  def fetch_random_token
    REDIS.srandmember(token_set_key)
  end

  def add_tokens(tokens)
    REDIS.sadd(token_set_key, tokens)
  end

  def remove_token(token)
    REDIS.srem(token_set_key, token)
  end

  def check_tokens
    list_tokens.each do |token|
      begin
        api_client(token).rate_limit!
      rescue Octokit::Unauthorized, Octokit::AccountSuspended
        puts "Removing token #{token}"
        remove_token(token)
      end
    end
  end

  def fetch_commits
    # load commits via rugged
    commits = []
    Dir.mktmpdir do |dir|
      Rugged::Repository.clone_at(git_clone_url, dir)
      repo = Rugged::Repository.new(dir)
      walker = Rugged::Walker.new(repo)
      walker.hide(repo.lookup(last_synced_commit)) if last_synced_commit
      walker.sorting(Rugged::SORT_DATE)
      walker.push(repo.head.target)
      walker.each do |commit|
        commits << {
          repository_id: id,
          sha: commit.oid,
          message: commit.message.strip,
          timestamp: commit.time.iso8601,
          merge: commit.parents.length > 1,
          author: "#{commit.author[:name]} <#{commit.author[:email]}>",
          committer: "#{commit.committer[:name]} <#{commit.committer[:email]}>",
          stats: commit.diff.stat
        }
      end
      walker.reset
      repo.close
    end
    commits
  end

  def sync_commits
    commit_hashes = fetch_commits
    return if commit_hashes.empty?
    Commit.upsert_all(commit_hashes) 
    update(last_synced_commit: commit_hashes.first[:sha], last_synced_at: Time.now)
  rescue => e
    puts "Error syncing commits for #{full_name}: #{e}"
  end

  private

  def api_client(token = nil, options = {})
    token = fetch_random_token if token.nil?
    Octokit::Client.new({access_token: token, auto_paginate: true}.merge(options))
  end
end
