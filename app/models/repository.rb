class Repository < ApplicationRecord
  class CloneError < StandardError; end
  class TimeoutError < StandardError; end
  class SyncError < StandardError; end
  belongs_to :host

  has_many :commits, dependent: :delete_all
  has_many :contributions, dependent: :delete_all
  # has_many :committers, through: :contributions

  validates :full_name, presence: true

  scope :active, -> { where(status: nil) }
  scope :visible, -> { active.where.not(last_synced_at: nil).where.not(total_commits: nil) }
  scope :created_after, ->(date) { where('created_at > ?', date) }
  scope :updated_after, ->(date) { where('updated_at > ?', date) }
  scope :owner, ->(owner) { where('full_name LIKE ?', "#{owner}/%") }

  scope :committer, ->(login) { 
    where("EXISTS (
      SELECT 1 FROM json_array_elements(committers::json) AS j
      WHERE j->>'login' = ?
    )", login)
  }

  scope :committer_email, ->(email) { 
    where("EXISTS (
      SELECT 1 FROM json_array_elements(committers::json) AS j
      WHERE j->>'email' = ?
    )", email)
  }

  scope :committer_login_or_email, ->(login,email) {
    where("EXISTS (
      SELECT 1 FROM json_array_elements(committers::json) AS j
      WHERE j->>'login' = ? OR j->>'email' = ?
    )", login, email)
  }

  before_save :set_owner

  def self.sync_least_recently_synced
    Repository.active.order('last_synced_at ASC').limit(100).each(&:sync_async)
  end

  def self.find_or_create_from_host(host, full_name)
    host.repositories.find_by('lower(full_name) = ?', full_name.downcase) ||
      host.repositories.create!(full_name: full_name)
  end

  def self.find_or_create_from_url(url)
    # Parse URL to extract host and repo name
    if url =~ /https?:\/\/([^\/]+)\/(.+)/
      host_name = $1
      full_name = $2.sub(/\.git$/, '') # Remove .git suffix if present
      
      host = Host.find_by(name: host_name)
      return nil unless host
      
      repo = host.repositories.find_by('lower(full_name) = ?', full_name.downcase)
      return repo if repo
    end
    
    # If not found locally, try external API
    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
      f.headers['User-Agent'] = 'commits.ecosyste.ms'
    end
    
    response = conn.get("api/v1/repositories/lookup?url=#{CGI.escape(url)}")
    return nil unless response.success?
    
    json = response.body
    host = Host.find_by(name: json['host']['name'])
    return nil unless host
    
    host.repositories.find_or_create_by(full_name: json['full_name'])
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

  def set_owner
    self.owner = full_name.split('/').first
  end

  def owner
    read_attribute(:owner) || full_name.split('/').first
  end

  def sync_async(remote_ip = '0.0.0.0')
    return if last_synced_at.present? && last_synced_at > 1.week.ago

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
      f.headers['User-Agent'] = 'commits.ecosyste.ms'
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
    self.description = json['description']
    self.stargazers_count = json['stargazers_count']
    self.fork = json['fork']
    self.archived = json['archived']
    self.icon_url = json['icon_url']
    self.size = json['size']
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

  def git_dir_args(dir)
    # Validate directory path to prevent directory traversal
    raise ArgumentError, "Invalid directory path" unless dir && File.directory?(dir)
    
    # Check if it's a bare repository (bare repos have HEAD file directly in the dir)
    # Non-bare repos have .git directory
    if File.exist?(File.join(dir, "HEAD"))
      ["--git-dir", dir]  # Separate arguments are safer than interpolation
    else
      ["-C", dir]
    end
  end
  
  def git_dir_arg(dir)
    # For backward compatibility with string interpolation
    git_dir_args(dir).join(" ")
  end
  
  def clone_repository(dir)
    # Clone into a subdirectory to keep the structure clean
    repo_path = File.join(dir, "repo")
    # Use --filter=blob:none to skip file contents (we only need commit history)
    # Use --single-branch since we only fetch commits from HEAD anyway
    # Prevent any credential prompts - fail immediately for private repos
    output = `export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/echo && git clone --filter=blob:none --single-branch --quiet #{git_clone_url.shellescape} #{repo_path.shellescape} 2>&1`
    unless $?.success?
      # Check if the repository has been deleted from GitHub or is private
      if output.include?("could not read Username") || 
         output.include?("Repository not found") || 
         output.include?("Authentication failed") ||
         output.include?("terminal prompts disabled")
        update_column(:status, 'not_found')
        raise CloneError, "Repository #{full_name} appears to be deleted or private"
      end
      raise CloneError, "Failed to clone #{full_name}: #{output}"
    end
  end

  # TODO support hg and svn repos

  def count_refs
    refs = `git ls-remote --heads --tags #{git_clone_url}`
    refs.lines.count
  rescue => e
    Rails.logger.error "Failed to count refs for #{full_name}: #{e.message}"
    0
  end

  def too_large?
    count_refs > 1000 || (size.present? && size > 500_000)
  end

  def sync_all(force: false)
    sync_details
    return if too_large?
    if status == 'not_found'
      # Update last_synced_at even for not_found repos to avoid repeated attempts
      update_column(:last_synced_at, Time.now)
      return
    end
    
    last_commit = fetch_head_sha
    
    # Skip early return checks if force is true
    unless force
      if !past_year_committers.nil? && last_synced_commit == last_commit && commits_count > 0
        update(last_synced_at: Time.now)
        return
      end
    end
    
    # Clear existing commits if force is true
    if force
      commits.delete_all
      update_columns(last_synced_commit: nil, total_commits: 0)
    end
    
    begin
      Dir.mktmpdir do |dir|
        # Clone repository once
        begin
          Timeout.timeout(60) { clone_repository(dir) }
        rescue Timeout::Error
          raise TimeoutError, "Clone timed out for #{full_name} after 60 seconds"
        end
        
        repo_dir = File.join(dir, "repo")
        
        # Count commits and update statistics
        counts = count_commits_internal(repo_dir)
        update(counts)
        
        # Sync commits
        sync_commits_batch(repo_dir, force: force)
        
        # Handle committers
        if committers
          fetch_all_logins
          create_committer_join_records
        end
        
        update(last_synced_at: Time.now)
      end
    rescue => e
      self.status = 'too_large' if e.message.include?('timed out') || e.message.include?('too many committers')
      self.save
      puts "Error syncing repository #{full_name}: #{e}"
    end
  end

  def count_commits
    sync_details
    return if too_large?
    return if status == 'not_found'
    
    last_commit = fetch_head_sha
    if !past_year_committers.nil? && last_synced_commit == last_commit && commits_count > 0
      update(last_synced_at: Time.now)
      return
    end
    
    begin
      Dir.mktmpdir do |dir|
        begin
          Timeout.timeout(60) { clone_repository(dir) }
        rescue Timeout::Error
          raise TimeoutError, "Clone timed out for #{full_name} after 60 seconds"
        end
        repo_dir = File.join(dir, "repo")
        counts = count_commits_internal(repo_dir)
        update(counts)

        if committers
          fetch_all_logins
          create_committer_join_records
        end
      end
    rescue => e
      self.status = 'too_large' if e.message.include?('timed out') || e.message.include?('too many committers')
      self.save
      puts "Error counting commits for #{full_name}: #{e}"
    end
  end

  def count_commits_internal(dir)
    # First check if this is a git repository
    last_commit = `git #{git_dir_arg(dir)} rev-parse HEAD 2>/dev/null`.strip
    return {} if last_commit.empty? || !$?.success?
    
    output = `git #{git_dir_arg(dir)} shortlog -s -n -e --no-merges HEAD 2>/dev/null`
    # Force UTF-8 encoding and replace invalid characters
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end

    past_year_output = `git #{git_dir_arg(dir)} shortlog -s -n -e --no-merges --since="1 year ago" HEAD 2>/dev/null`
    # Force UTF-8 encoding and replace invalid characters
    past_year_output = past_year_output.force_encoding('UTF-8')
    unless past_year_output.valid_encoding?
      past_year_output = past_year_output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end

    committers = parse_commit_counts(output)

    return {} if committers.size > 10000

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
      mean_commits: committers.any? ? (total_commits.to_f / committers.length) : 0,
      dds: committers.any? ? 1 - (committers.first[:count].to_f / total_commits) : 0,
      past_year_committers: past_year_committers,
      past_year_total_commits: past_year_total_commits,
      past_year_total_committers: past_year_committers.length,
      past_year_total_bot_commits: past_year_total_bot_commits,
      past_year_total_bot_committers: past_year_committers.select{|h| h[:name].ends_with?('[bot]')}.length,
      past_year_mean_commits: past_year_mean_commits,
      past_year_dds: past_year_dds,
      last_synced_at: Time.now
    }
  end

  def parse_commit_counts(output)
    # parse the output of the git command
    # return an array of hashes with the author and commit count
    lines = output.split("\n").map do |line|
      count, author = line.split("\t")
      name, email = author.split("<")
      email.gsub!(/[<>]/, '')
      # Remove null characters from name and email
      name = name.strip.gsub("\u0000", '') if name
      email = email.gsub("\u0000", '') if email
      login = fetch_existing_login(email)
      { name: name, email: email, login: login, count: count.to_i }
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
    commits = []
    Dir.mktmpdir do |dir|
      clone_repository(dir)
      repo_dir = File.join(dir, "repo")
      commits = fetch_commits_internal(repo_dir)
    end
    commits
  end
  
  def fetch_commits_in_batches(&block)
    Dir.mktmpdir do |dir|
      clone_repository(dir)
      repo_dir = File.join(dir, "repo")
      
      offset = 0
      batch_size = 5000
      
      loop do
        batch = fetch_commits_batch(repo_dir, offset, batch_size)
        break if batch.empty?
        
        yield batch
        offset += batch_size
        
        # Stop if we got less than batch_size (end of commits)
        break if batch.size < batch_size
      end
    end
  end
  
  def fetch_commits_batch(dir, offset, limit)
    head_check = `git #{git_dir_arg(dir.shellescape)} rev-parse HEAD 2>/dev/null`.strip
    return [] if head_check.empty?
    
    format = "%H%x00%P%x00%an%x00%ae%x00%cn%x00%ce%x00%aI%x00%B"
    
    git_cmd = ["git"] + git_dir_args(dir) + ["log", "--format=#{format}", "--numstat", "-z", 
               "--skip=#{offset}", "-n", limit.to_s]
    
    if last_synced_commit && total_commits && total_commits > 0
      git_cmd << "#{last_synced_commit}..HEAD"
    else
      git_cmd << "HEAD"
    end
    
    require 'open3'
    output, _stderr, _status = Open3.capture3(*git_cmd)
    # Force UTF-8 encoding and replace invalid characters
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    # Same parsing logic as fetch_commits_internal
    commits = []
    repo_id = id
    
    fields = output.chomp("\0").split("\0")
    
    i = 0
    while i < fields.length
      # Need at least 8 fields for a complete commit
      break if i + 7 >= fields.length
      
      sha = fields[i]
      parents = fields[i + 1]
      author_name = fields[i + 2]
      author_email = fields[i + 3]
      committer_name = fields[i + 4]
      committer_email = fields[i + 5]
      timestamp = fields[i + 6]
      message = fields[i + 7]
      
      # Move to next set of fields
      i += 8
      
      # Check if there's numstat data (it would be the next field)
      additions = 0
      deletions = 0
      files = 0
      
      # Skip numstat parsing if present
      if i < fields.length && fields[i].match(/^\d+\t\d+\t/)
        # Has numstat, skip it
        i += 1
      end
      
      cleaned_message = message.strip
      
      commits << {
        repository_id: repo_id,
        sha: sha,
        message: cleaned_message,
        timestamp: timestamp,
        merge: parents.include?(' '),
        author: "#{author_name} <#{author_email}>",
        committer: "#{committer_name} <#{committer_email}>",
        stats: [additions, deletions, files],
        co_author_email: Commit.extract_co_author_from_message(cleaned_message)
      }
    end
    
    commits
  end

  def commits_count
    commits.count
  end

  def fetch_commits_internal(dir)
    head_check = `git #{git_dir_arg(dir.shellescape)} rev-parse HEAD 2>/dev/null`.strip
    return [] if head_check.empty?
    
    # Use NUL delimiter to safely handle multi-line commit messages
    # %B gets the full commit message including body (not just subject line)
    format = "%H%x00%P%x00%an%x00%ae%x00%cn%x00%ce%x00%aI%x00%B"
    
    git_cmd = ["git"] + git_dir_args(dir) + ["log", "--format=#{format}", "--numstat", "-z", "-n", "5000"]
    
    if last_synced_commit && total_commits && total_commits > 0
      git_cmd << "#{last_synced_commit}..HEAD"
    else
      git_cmd << "HEAD"
    end
    
    require 'open3'
    output, _stderr, _status = Open3.capture3(*git_cmd)
    # Force UTF-8 encoding and replace invalid characters
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    commits = []
    repo_id = id # Cache to avoid repeated method calls
    
    # Git log with -z flag adds an extra NUL after the format string output
    # So we get: sha\0parents\0author_name\0author_email\0committer_name\0committer_email\0timestamp\0message\0numstat\0
    # Split and process in groups of 8 fields (the message field ends with the format, numstat is separate)
    
    # Remove any trailing NUL bytes and split
    fields = output.chomp("\0").split("\0")
    
    # Process commits - with -z flag, each commit's format output ends, then numstat follows
    i = 0
    while i < fields.length
      # Need at least 8 fields for a complete commit
      break if i + 7 >= fields.length
      
      sha = fields[i]
      parents = fields[i + 1]
      author_name = fields[i + 2]
      author_email = fields[i + 3]
      committer_name = fields[i + 4]
      committer_email = fields[i + 5]
      timestamp = fields[i + 6]
      message = fields[i + 7]
      
      # Move to next set of fields
      i += 8
      
      # Check if there's numstat data (it would be the next field)
      additions = 0
      deletions = 0
      files = 0
      
      # Skip numstat parsing if present (would be in fields[i] if exists)
      if i < fields.length && fields[i].match(/^\d+\t\d+\t/)
        # Has numstat, skip it
        i += 1
      end
      
      cleaned_message = message.strip
      
      commits << {
        repository_id: repo_id,
        sha: sha,
        message: cleaned_message,
        timestamp: timestamp,
        merge: parents.include?(' '),
        author: "#{author_name} <#{author_email}>",
        committer: "#{committer_name} <#{committer_email}>",
        stats: [additions, deletions, files],
        co_author_email: Commit.extract_co_author_from_message(cleaned_message)
      }
    end
    
    commits
  end

  def sync_commits(incremental: true)
    # Skip syncing if repository is not found
    return if status == 'not_found'
    
    if incremental
      # Use incremental sync by default for better performance and resumability
      result = sync_commits_incremental
      
      # Handle timeout as partial progress
      if result == :timeout
        Rails.logger.info "Incremental sync made partial progress for #{full_name}"
        return true
      end
      
      result
    else
      sync_commits_regular
    end
  end
  
  def sync_commits_batch(repo_dir, force: false)
    # Sync commits using simple batch pagination
    start_time = Time.now
    timeout_duration = 300 # 5 minutes
    total_processed = 0
    
    begin
      # Count total commits in the repository
      total_repo_commits = count_commits_in_repo(repo_dir)
      
      # Check what we already have
      existing_count = commits.count
      
      # Quick check: if we already have all commits, we're done (unless force is true)
      if existing_count >= total_repo_commits && !force
        # Just update the last_synced_commit to current HEAD
        head_sha = `git #{git_dir_arg(repo_dir)} rev-parse HEAD`.strip
        if head_sha.present?
          update_columns(
            last_synced_commit: head_sha,
            last_synced_at: Time.current
          )
        end
        return existing_count
      end
      
      # Adjust batch size based on repo size
      batch_size = if total_repo_commits > 100000
        10000
      elsif total_repo_commits > 50000
        5000
      elsif total_repo_commits > 10000
        2000
      else
        1000
      end
      
      # Process commits in batches using --skip and -n
      offset = 0
      
      loop do
        break if (Time.now - start_time) >= timeout_duration
        
        # Fetch a batch of commits
        batch = fetch_commits_paginated(repo_dir, offset, batch_size, last_synced_commit)
        
        break if batch.empty?
        
        # Clean the batch
        cleaned_batch = batch.map do |commit|
          commit.transform_values do |value|
            value.is_a?(String) ? value.gsub("\u0000", '') : value
          end
        end
        
        # Deduplicate by SHA to prevent PG::CardinalityViolation
        cleaned_batch = cleaned_batch.uniq { |c| c[:sha] }
        
        if cleaned_batch.any?
          # Insert this batch
          cleaned_batch.each_slice(1000) do |chunk|
            Commit.upsert_all(
              chunk,
              unique_by: [:repository_id, :sha],
              returning: false
            )
          end
        end
        
        total_processed += cleaned_batch.size
        offset += batch_size
        
        # Continue until we get an empty batch
        # (Don't stop on batch.size < batch_size as that's still valid)
      end
      
      # Update the last synced commit to HEAD
      head_sha = `git #{git_dir_arg(repo_dir)} rev-parse HEAD`.strip
      if head_sha.present?
        update_columns(
          last_synced_commit: head_sha,
          last_synced_at: Time.current
        )
      end
      
      total_processed
    rescue => e
      Rails.logger.error "Error syncing commits for #{full_name}: #{e.message}"
      raise SyncError, "Failed to sync commits for #{full_name}: #{e.message}"
    end
  end
  
  # OLD METHOD - should not be used
  def sync_commits_from_dir(repo_dir)
    # Sync commits using already cloned repository directory
    start_time = Time.now
    timeout_duration = 300 # 5 minutes
    total_processed = 0
    
    begin
      # Get date range
      oldest_commit_date = get_oldest_commit_date(repo_dir)
      newest_commit_date = get_newest_commit_date(repo_dir)
      
      Rails.logger.info "Incremental sync for #{full_name}: repo oldest=#{oldest_commit_date}, newest=#{newest_commit_date}"
      
      return nil if oldest_commit_date.nil? || newest_commit_date.nil?
      
      # Count total commits in the repository
      total_repo_commits = count_commits_in_repo(repo_dir)
      Rails.logger.info "Repository has #{total_repo_commits} total commits"
      
      # Get existing commit count
      existing_commits = commits.count
      Rails.logger.info "Database has #{existing_commits} existing commits for this repo"
      
      if existing_commits >= total_repo_commits
        Rails.logger.info "All commits already synced (#{existing_commits} >= #{total_repo_commits})"
        return true
      end
      
      # Process commits in date chunks
      current_date = oldest_commit_date.to_date
      end_date = newest_commit_date.to_date
      
      while current_date <= end_date && (Time.now - start_time) < timeout_duration
        chunk_end = [current_date + 30.days, end_date].min
        
        batch = fetch_commits_by_date_range(repo_dir, current_date, chunk_end)
        
        if batch.any?
          # Clean and insert batch
          cleaned_batch = batch.map do |commit|
            commit.transform_values do |value|
              value.is_a?(String) ? value.gsub("\u0000", '') : value
            end
          end
          
          # Deduplicate by SHA to prevent PG::CardinalityViolation
          cleaned_batch = cleaned_batch.uniq { |c| c[:sha] }
          
          Rails.logger.info "Batch had #{batch.size} commits, #{cleaned_batch.size} after deduplication"
          
          if cleaned_batch.any?
            Commit.upsert_all(
              cleaned_batch,
              unique_by: [:repository_id, :sha],
              returning: false
            )
          end
          
          total_processed += cleaned_batch.size
        end
        
        current_date = chunk_end + 1.day
      end
      
      # Update last synced commit
      latest_sha = `git -C #{repo_dir.shellescape} rev-parse HEAD`.strip
      update_column(:last_synced_commit, latest_sha) if latest_sha.present?
      
      Rails.logger.info "Processed #{total_processed} commits in #{(Time.now - start_time).round(2)}s"
      
      if (Time.now - start_time) >= timeout_duration
        Rails.logger.info "Sync timed out after processing #{total_processed} commits"
        :timeout
      else
        true
      end
    rescue => e
      Rails.logger.error "Error syncing commits from dir: #{e.message}"
      raise
    end
  end
  
  def sync_commits_regular
    Timeout.timeout(300) do
      commit_hashes = fetch_commits
      return if commit_hashes.empty?
      
      # Clean commit data to remove null bytes
      commit_hashes = commit_hashes.map do |commit|
        commit.transform_values do |value|
          if value.is_a?(String)
            value.gsub("\u0000", '')
          else
            value
          end
        end
      end
      
      # Batch insert for better performance
      commit_hashes.each_slice(1000) do |batch|
        Commit.upsert_all(
          batch,
          unique_by: [:repository_id, :sha],
          returning: false
        )
      end
      
      # Update last synced commit
      if commit_hashes.any?
        update_column(:last_synced_commit, commit_hashes.first[:sha])
      end
    end
  rescue Timeout::Error => e
    Rails.logger.error "Sync commits timeout for #{full_name} after 5 minutes"
    raise TimeoutError, "Sync commits timed out for #{full_name} after 5 minutes"
  rescue => e
    Rails.logger.error "Error syncing commits for #{full_name}: #{e.message}"
    # For other errors, we might want to retry, so we still raise
    raise SyncError, "Failed to sync commits for #{full_name}: #{e.message}"
  end
  
  def sync_commits_incremental
    start_time = Time.now
    timeout_duration = 300 # 5 minutes
    total_processed = 0
    
    Dir.mktmpdir do |dir|
      # Benchmark: Clone repository
      clone_start = Time.now
      clone_repository(dir)
      repo_dir = File.join(dir, "repo")
      clone_duration = Time.now - clone_start
      Rails.logger.info "[BENCHMARK] Clone repository #{full_name}: #{clone_duration.round(2)}s"
      
      # Benchmark: Get date range
      date_range_start = Time.now
      oldest_commit_date = get_oldest_commit_date(repo_dir)
      newest_commit_date = get_newest_commit_date(repo_dir)
      date_range_duration = Time.now - date_range_start
      Rails.logger.info "[BENCHMARK] Get date range: #{date_range_duration.round(2)}s"
      
      Rails.logger.info "Incremental sync for #{full_name}: repo oldest=#{oldest_commit_date}, newest=#{newest_commit_date}"
      
      if oldest_commit_date.nil? || newest_commit_date.nil?
        Rails.logger.error "Date range is nil, returning early"
        return nil
      end
      
      # Count total commits in the repository (FAST!)
      count_start = Time.now
      total_repo_commits = count_commits_in_repo(repo_dir)
      count_duration = Time.now - count_start
      Rails.logger.info "[BENCHMARK] Count commits in repo: #{count_duration.round(2)}s"
      Rails.logger.info "Repository has #{total_repo_commits} total commits"
      
      if total_repo_commits > 100000
        Rails.logger.warn "WARNING: Very large repository with #{total_repo_commits} commits!"
        Rails.logger.warn "Consider using a different sync strategy or increasing timeout"
      elsif total_repo_commits > 50000
        Rails.logger.warn "WARNING: Large repository with #{total_repo_commits} commits - sync may take a while"
      end
      
      # Adjust batch size based on repo size
      batch_size = if total_repo_commits > 100000
        10000  # Larger batches for huge repos
      elsif total_repo_commits > 50000
        5000
      else
        2000  # Smaller batches for normal repos
      end
      Rails.logger.info "Using batch size: #{batch_size}"
      
      # Check what we already have in the database
      existing_count = commits.count
      
      Rails.logger.info "Found #{existing_count} existing commits in database"
      Rails.logger.info "Repository has #{total_repo_commits} total commits"
      
      # Quick check: if we already have all commits, we're done
      if existing_count >= total_repo_commits
        Rails.logger.info "Already have all commits (#{existing_count} in DB, #{total_repo_commits} in repo)"
        
        # Just update the last_synced_commit to current HEAD
        head_sha = `git #{git_dir_arg(repo_dir)} rev-parse HEAD`.strip
        if head_sha.present?
          update_columns(
            last_synced_commit: head_sha,
            last_synced_at: Time.current
          )
        end
        return existing_count
      end
      
      Rails.logger.info "Need to sync commits (have #{existing_count}, repo has #{total_repo_commits})"
      
      # Process commits in batches using --skip and -n (FAST!)
      # The database upsert will handle duplicates automatically
      Rails.logger.info "Fetching commits for #{full_name} in batches"
      
      # batch_size is already set above based on repo size
      offset = 0  # Always start from 0 to get newest commits first
      
      loop do
        # Fetch a batch of commits
        fetch_start = Time.now
        batch = fetch_commits_paginated(repo_dir, offset, batch_size, last_synced_commit)
        fetch_duration = Time.now - fetch_start
        
        break if batch.empty?
        
        Rails.logger.info "[BENCHMARK] Fetched batch of #{batch.size} commits (offset #{offset}) in #{fetch_duration.round(2)}s"
        
        # Clean the batch
        clean_start = Time.now
        cleaned_batch = batch.map do |commit|
          commit.transform_values do |value|
            value.is_a?(String) ? value.gsub("\u0000", '') : value
          end
        end
        clean_duration = Time.now - clean_start
        Rails.logger.info "[BENCHMARK] Cleaned #{batch.size} commits in #{clean_duration.round(3)}s"
        
        # Insert this batch
        db_start = Time.now
        cleaned_batch.each_slice(1000) do |chunk|
          Commit.upsert_all(
            chunk,
            unique_by: [:repository_id, :sha],
            returning: false
          )
        end
        db_duration = Time.now - db_start
        Rails.logger.info "[BENCHMARK] Inserted #{batch.size} commits to DB in #{db_duration.round(2)}s"
        
        total_processed += batch.size
        offset += batch_size
        
        # Stop if we got less than batch_size (means we're at the end)
        break if batch.size < batch_size
      end
      
      # Get the most recent commit we actually synced
      # Don't use HEAD because we might not have synced all commits
      last_synced = commits.order('timestamp DESC').first
      
      # Update tracking info with the actual last synced commit
      if last_synced
        update_columns(
          last_synced_commit: last_synced.sha,
          last_synced_at: Time.current
        )
        Rails.logger.info "Updated last_synced_commit to #{last_synced.sha}"
      end
      
      total_duration = Time.now - start_time
      Rails.logger.info "[BENCHMARK] Total sync time for #{full_name}: #{total_duration.round(2)}s for #{total_processed} commits"
      Rails.logger.info "[BENCHMARK] Average: #{(total_duration / total_processed * 1000).round(2)}ms per commit" if total_processed > 0
      Rails.logger.info "Successfully synced #{total_processed} commits for #{full_name}"
      total_processed
    end
  rescue => e
    Rails.logger.error "Error in incremental sync for #{full_name}: #{e.message}"
    raise SyncError, "Failed to sync commits incrementally for #{full_name}: #{e.message}"
  end
  
  def count_commits_in_repo(dir)
    # Use rev-list --count which is VERY fast
    git_cmd = ["git"] + git_dir_args(dir) + ["rev-list", "--count", "HEAD"]
    output = `#{git_cmd.join(' ')}`.strip
    output.to_i
  rescue => e
    Rails.logger.error "Failed to count commits: #{e.message}"
    0
  end
  
  def get_oldest_commit_date(dir)
    # Use head -1 instead of -n 1 because --reverse with -n 1 doesn't work properly
    output = `git #{git_dir_arg(dir.shellescape)} log --reverse --format=%aI 2>&1 | head -1`.strip
    
    if output.empty? || output.include?("fatal:")
      Rails.logger.error "Failed to get oldest commit date for #{full_name}: #{output}"
      return nil
    end
    
    Time.parse(output)
  rescue => e
    Rails.logger.error "Error parsing oldest commit date for #{full_name}: #{e.message}"
    nil
  end
  
  def get_newest_commit_date(dir)
    output = `git #{git_dir_arg(dir.shellescape)} log --format=%aI -n 1 2>&1`.strip
    
    if $?.exitstatus != 0
      Rails.logger.error "Failed to get newest commit date for #{full_name}: #{output}"
      return nil
    end
    
    return nil if output.empty?
    Time.parse(output)
  rescue => e
    Rails.logger.error "Error parsing newest commit date for #{full_name}: #{e.message}"
    nil
  end
  
  def fetch_commits_paginated(dir, offset, limit, after_sha = nil)
    format = "%H%x00%P%x00%an%x00%ae%x00%cn%x00%ce%x00%aI%x00%B"
    
    # Build command with pagination
    git_cmd = ["git"] + git_dir_args(dir) + [
      "log",
      "--format=#{format}",
      "-z",  # NUL-delimited output
      "--skip=#{offset}",
      "-n", limit.to_s,
      "HEAD"
    ]
    
    require 'open3'
    output, stderr, status = Open3.capture3(*git_cmd)
    
    unless status.exitstatus == 0
      Rails.logger.error "Git log failed: exit #{status.exitstatus}, stderr: #{stderr}"
      return []
    end
    
    # Parse the output
    commits = parse_commit_output(output)
    
    commits
  end
  
  def fetch_all_commits_fast(dir, after_sha = nil)
    format = "%H%x00%P%x00%an%x00%ae%x00%cn%x00%ce%x00%aI%x00%B"
    
    # Build command - get ALL commits without date filtering
    git_cmd = ["git"] + git_dir_args(dir) + [
      "log",
      "--format=#{format}",
      "--numstat", "-z"
      # Removed --all since we clone with --single-branch
    ]
    
    # If we have a last synced commit, only get newer ones
    if after_sha && commits.exists?(sha: after_sha)
      git_cmd << "#{after_sha}..HEAD"
    end
    
    require 'open3'
    output, _stderr, status = Open3.capture3(*git_cmd)
    
    unless status.exitstatus == 0
      Rails.logger.error "Git log failed: exit #{status.exitstatus}"
      return []
    end
    
    # Parse the output
    parse_commit_output(output)
  end
  
  def parse_commit_output(output)
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    commits = []
    repo_id = id
    
    # Split by NUL and process in groups of 8 fields per commit
    fields = output.chomp("\0").split("\0")
    
    # Process each group of 8 fields as a commit
    i = 0
    while i + 7 < fields.length
      sha = fields[i]
      parents = fields[i + 1]
      author_name = fields[i + 2]
      author_email = fields[i + 3]
      committer_name = fields[i + 4]
      committer_email = fields[i + 5]
      timestamp = fields[i + 6]
      message = fields[i + 7]
      
      cleaned_message = message.strip
      
      commits << {
        repository_id: repo_id,
        sha: sha,
        message: cleaned_message,
        timestamp: timestamp,
        merge: parents && parents.include?(' '),
        author: "#{author_name} <#{author_email}>",
        committer: "#{committer_name} <#{committer_email}>",
        stats: [0, 0, 0],  # No stats without numstat
        co_author_email: Commit.extract_co_author_from_message(cleaned_message)
      }
      
      i += 8
    end
    
    commits
  end
  
  def parse_commit_output(output)
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    commits = []
    repo_id = id
    
    # With -z flag and NUL format, parse carefully
    fields = output.chomp("\0").split("\0")
    
    i = 0
    while i < fields.length
      # Need at least 8 fields for a complete commit
      break if i + 7 >= fields.length
      
      sha = fields[i]
      parents = fields[i + 1]
      author_name = fields[i + 2]
      author_email = fields[i + 3]
      committer_name = fields[i + 4]
      committer_email = fields[i + 5]
      timestamp = fields[i + 6]
      message = fields[i + 7]
      
      # Move to next set of fields
      i += 8
      
      additions = 0
      deletions = 0  
      files = 0
      
      # Check if there's numstat data (it would be in the next field)
      # Numstat format is like: "1\t2\tfile.txt\n3\t4\tother.txt"
      if i < fields.length && !fields[i].empty?
        numstat = fields[i]
        if numstat.match(/^\d+\t\d+\t/)
          numstat.each_line do |line|
            if match = line.match(/^(\d+|-)\t(\d+|-)\t/)
              add = match[1] == '-' ? 0 : match[1].to_i
              del = match[2] == '-' ? 0 : match[2].to_i
              additions += add
              deletions += del
              files += 1
            end
          end
          i += 1 # Skip the numstat field
        end
      end
      
      cleaned_message = message.strip
      
      commits << {
        repository_id: repo_id,
        sha: sha,
        message: cleaned_message,
        timestamp: timestamp,
        merge: parents.include?(' '),
        author: "#{author_name} <#{author_email}>",
        committer: "#{committer_name} <#{committer_email}>",
        stats: [files, additions, deletions],
        co_author_email: Commit.extract_co_author_from_message(cleaned_message)
      }
    end
    
    commits
  end
  
  def fetch_commits_by_date_range(dir, since_date, until_date)
    format = "%H%x00%P%x00%an%x00%ae%x00%cn%x00%ce%x00%aI%x00%B"
    
    # Build command as array for safety (no shell interpolation)
    git_cmd = ["git"] + git_dir_args(dir) + [
      "log",
      "--format=#{format}",
      "--numstat", "-z",
      "--since=#{since_date.iso8601}",
      "--until=#{until_date.iso8601}"
      # Removed --all since we clone with --single-branch
    ]
    
    # Benchmark: Git command execution
    require 'open3'
    output, _stderr, status = Open3.capture3(*git_cmd)
    git_duration = Time.now - git_start
    Rails.logger.info "[BENCHMARK] Git log command (#{since_date.to_date} to #{until_date.to_date}): #{git_duration.round(3)}s, output size: #{output.bytesize} bytes"
    
    # Log if there's an error
    if status.exitstatus != 0
      Rails.logger.error "Git log failed for #{since_date} to #{until_date}: #{output}"
      return []
    end
    
    # Force UTF-8 encoding and replace invalid characters
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    commits = []
    repo_id = id
    
    # Use same NUL parsing as other methods
    fields = output.chomp("\0").split("\0")
    
    i = 0
    while i < fields.length
      # Need at least 8 fields for a complete commit
      break if i + 7 >= fields.length
      
      sha = fields[i]
      parents = fields[i + 1]
      author_name = fields[i + 2]
      author_email = fields[i + 3]
      committer_name = fields[i + 4]
      committer_email = fields[i + 5]
      timestamp = fields[i + 6]
      message = fields[i + 7]
      
      # Move to next set of fields
      i += 8
      
      additions = 0
      deletions = 0  
      files = 0
      
      # Skip numstat parsing if present (would be in fields[i] if exists)
      if i < fields.length && fields[i].match(/^\d+\t\d+\t/)
        # Has numstat, skip it
        i += 1
      end
      
      cleaned_message = message.strip
      
      commits << {
        repository_id: repo_id,
        sha: sha,
        message: cleaned_message,
        timestamp: timestamp,
        merge: parents.include?(' '),
        author: "#{author_name} <#{author_email}>",
        committer: "#{committer_name} <#{committer_email}>",
        stats: [additions, deletions, files],
        co_author_email: Commit.extract_co_author_from_message(cleaned_message)
      }
    end
    
    commits
  end
  
  def sync_commits_streaming
    Timeout.timeout(300) do
      latest_sha = nil
      total_processed = 0
      
      fetch_commits_in_batches do |batch|
        next if batch.empty?
        
        # Track the latest commit SHA from first batch
        latest_sha ||= batch.first[:sha]
        
        # Clean commit data to remove null bytes
        cleaned_batch = batch.map do |commit|
          commit.transform_values do |value|
            if value.is_a?(String)
              value.gsub("\u0000", '')
            else
              value
            end
          end
        end
        
        # Efficient bulk insert with conflict resolution
        Commit.upsert_all(
          cleaned_batch,
          unique_by: [:repository_id, :sha],
          returning: false
        )
        
        total_processed += batch.size
        Rails.logger.info "Processed #{total_processed} commits for #{full_name}"
      end
      
      # Update last synced commit
      if latest_sha
        update_columns(
          last_synced_commit: latest_sha,
          last_synced_at: Time.current
        )
      end
      
      total_processed
    end
  rescue Timeout::Error => e
    Rails.logger.error "Sync commits streaming timeout for #{full_name} after 5 minutes"
    raise TimeoutError, "Sync commits streaming timed out for #{full_name} after 5 minutes"
  rescue => e
    Rails.logger.error "Error in streaming sync for #{full_name}: #{e.message}"
    raise SyncError, "Failed to sync commits (streaming) for #{full_name}: #{e.message}"
  end

  def committer_records
    return [] if committers.nil?
    grouped_committers = committers.map do |committer|
      next unless committer['login'].present? || committer['email'].present?
    
      c = host.committers.find_by(login: committer['login']) if committer['login'].present?
      c ||= host.committers.email(committer['email']).first
    
      next unless c
    
      { committer_id: c.id, commit_count: committer['count'] }
    end.compact
    
    grouped_committers = grouped_committers.group_by { |c| c[:committer_id] }.map do |committer_id, records|
      {
        committer_id: committer_id,
        commit_count: records.sum { |r| r[:commit_count].to_i }
      }
    end
  end

  def create_committer_join_records
    committer_records.each do |record|
      Contribution.find_or_create_by(repository_id: id, committer_id: record[:committer_id]) do |contribution|
        contribution.commit_count = record[:commit_count]
      end
    end
  end

  private

  def api_client(token = nil, options = {})
    token = fetch_random_token if token.nil?
    Octokit::Client.new({access_token: token}.merge(options))
  end
end
