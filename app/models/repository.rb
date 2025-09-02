class Repository < ApplicationRecord
  class CloneError < StandardError; end
  class TimeoutError < StandardError; end
  class SyncError < StandardError; end
  belongs_to :host

  has_many :commits
  has_many :contributions
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

  def clone_repository(dir)
    output = `git clone --quiet #{git_clone_url.shellescape} #{dir.shellescape} 2>&1`
    unless $?.success?
      # Check if the repository has been deleted from GitHub
      if output.include?("could not read Username") || output.include?("Repository not found")
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

  def count_commits
    sync_details
    return if too_large?
    return if status == 'not_found'
    last_commit = fetch_head_sha

    if !past_year_committers.nil? && last_synced_commit == last_commit && commits_count > 0
      update(last_synced_at: Time.now)
    else
      begin
        Dir.mktmpdir do |dir|
          begin
            Timeout.timeout(60) { clone_repository(dir) }
          rescue Timeout::Error
            raise TimeoutError, "Clone timed out for #{full_name} after 60 seconds"
          end
          counts = count_commits_internal(dir)
          # commit_hashes = fetch_commits_internal(repo)
          # Commit.upsert_all(commit_hashes) unless commit_hashes.empty?
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
  end

  def count_commits_internal(dir)
    last_commit = `git -C #{dir} rev-parse HEAD`.strip
    output = `git -C #{dir} shortlog -s -n -e --no-merges HEAD`
    # Force UTF-8 encoding and replace invalid characters
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end

    past_year_output = `git -C #{dir} shortlog -s -n -e --no-merges --since="1 year ago" HEAD`
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
      commits = fetch_commits_internal(dir)
    end
    commits
  end
  
  def fetch_commits_in_batches(&block)
    Dir.mktmpdir do |dir|
      clone_repository(dir)
      
      offset = 0
      batch_size = 5000
      
      loop do
        batch = fetch_commits_batch(dir, offset, batch_size)
        break if batch.empty?
        
        yield batch
        offset += batch_size
        
        # Stop if we got less than batch_size (end of commits)
        break if batch.size < batch_size
      end
    end
  end
  
  def fetch_commits_batch(dir, offset, limit)
    head_check = `git -C #{dir.shellescape} rev-parse HEAD 2>/dev/null`.strip
    return [] if head_check.empty?
    
    format = "%H|%s|%aI|%an|%ae|%cn|%ce|%P"
    
    git_cmd = ["git", "-C", dir, "log", "--format=#{format}", "--numstat", "-z", 
               "--skip=#{offset}", "-n", limit.to_s]
    
    if last_synced_commit && total_commits && total_commits > 0
      git_cmd << "#{last_synced_commit}..HEAD"
    else
      git_cmd << "HEAD"
    end
    
    output = `#{git_cmd.shelljoin} 2>/dev/null`
    # Force UTF-8 encoding and replace invalid characters
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    commits = []
    repo_id = id
    
    output.split("\0").each do |commit_block|
      next if commit_block.empty?
      
      lines = commit_block.lines
      next if lines.empty?
      
      header = lines.shift
      parts = header.split('|', 8)
      next unless parts.length == 8
      
      sha, message, timestamp, author_name, author_email, committer_name, committer_email, parents = parts
      
      additions = 0
      deletions = 0  
      files = 0
      
      lines.each do |line|
        if match = line.match(/^(\d+|-)\t(\d+|-)\t/)
          add = match[1] == '-' ? 0 : match[1].to_i
          del = match[2] == '-' ? 0 : match[2].to_i
          additions += add
          deletions += del
          files += 1
        end
      end
      
      commits << {
        repository_id: repo_id,
        sha: sha,
        message: message.strip.gsub("\u0000", ''),
        timestamp: timestamp,
        merge: parents.include?(' '),
        author: "#{author_name} <#{author_email}>".gsub("\u0000", ''),
        committer: "#{committer_name} <#{committer_email}>".gsub("\u0000", ''),
        stats: [additions, deletions, files]
      }
    end
    
    commits
  end

  def commits_count
    commits.count
  end

  def fetch_commits_internal(dir)
    head_check = `git -C #{dir.shellescape} rev-parse HEAD 2>/dev/null`.strip
    return [] if head_check.empty?
    
    # Use a more efficient format with delimiter
    format = "%H|%s|%aI|%an|%ae|%cn|%ce|%P"
    
    git_cmd = ["git", "-C", dir, "log", "--format=#{format}", "--numstat", "-z", "-n", "5000"]
    
    if last_synced_commit && total_commits && total_commits > 0
      git_cmd << "#{last_synced_commit}..HEAD"
    else
      git_cmd << "HEAD"
    end
    
    output = `#{git_cmd.shelljoin} 2>/dev/null`
    # Force UTF-8 encoding and replace invalid characters
    output = output.force_encoding('UTF-8')
    unless output.valid_encoding?
      output = output.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    commits = []
    repo_id = id # Cache to avoid repeated method calls
    
    # Split on null character for more reliable parsing
    output.split("\0").each do |commit_block|
      next if commit_block.empty?
      
      lines = commit_block.lines
      next if lines.empty?
      
      # Parse header line efficiently
      header = lines.shift
      parts = header.split('|', 8)
      next unless parts.length == 8
      
      sha, message, timestamp, author_name, author_email, committer_name, committer_email, parents = parts
      
      # Calculate stats efficiently
      additions = 0
      deletions = 0  
      files = 0
      
      lines.each do |line|
        if match = line.match(/^(\d+|-)\t(\d+|-)\t/)
          add = match[1] == '-' ? 0 : match[1].to_i
          del = match[2] == '-' ? 0 : match[2].to_i
          additions += add
          deletions += del
          files += 1
        end
      end
      
      commits << {
        repository_id: repo_id,
        sha: sha,
        message: message.strip.gsub("\u0000", ''),
        timestamp: timestamp,
        merge: parents.include?(' '),
        author: "#{author_name} <#{author_email}>".gsub("\u0000", ''),
        committer: "#{committer_name} <#{committer_email}>".gsub("\u0000", ''),
        stats: [additions, deletions, files]
      }
    end
    
    commits
  end

  def sync_commits(incremental: true)
    # Skip syncing if repository is not found
    return if status == 'not_found'
    
    if incremental
      # Use incremental sync by default for better performance and resumability
      sync_commits_incremental
    else
      sync_commits_regular
    end
  end
  
  def sync_commits_regular
    Timeout.timeout(900) do
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
    Rails.logger.error "Sync commits timeout for #{full_name} after 15 minutes"
    raise TimeoutError, "Sync commits timed out for #{full_name} after 15 minutes"
  rescue => e
    Rails.logger.error "Error syncing commits for #{full_name}: #{e.message}"
    # For other errors, we might want to retry, so we still raise
    raise SyncError, "Failed to sync commits for #{full_name}: #{e.message}"
  end
  
  def sync_commits_incremental
    start_time = Time.now
    timeout_duration = 900 # 15 minutes
    total_processed = 0
    latest_sha = nil
    
    Dir.mktmpdir do |dir|
      clone_repository(dir)
      
      # Get the date range for commits in the repository
      oldest_commit_date = get_oldest_commit_date(dir)
      newest_commit_date = get_newest_commit_date(dir)
      
      Rails.logger.info "Incremental sync for #{full_name}: repo oldest=#{oldest_commit_date}, newest=#{newest_commit_date}"
      
      if oldest_commit_date.nil? || newest_commit_date.nil?
        Rails.logger.error "Date range is nil, returning early"
        return nil
      end
      
      # Check what we already have in the database
      existing_count = commits.count
      
      if existing_count > 0
        oldest_synced = commits.minimum(:timestamp)
        newest_synced = commits.maximum(:timestamp)
        Rails.logger.info "Found #{existing_count} existing commits from #{oldest_synced} to #{newest_synced}"
        
        # If we have a good number of commits and they're recent, just get new ones
        if existing_count > 1000 && newest_synced && newest_synced > 1.week.ago
          Rails.logger.info "Many recent commits found, only syncing newer commits"
          oldest_commit_date = newest_synced
        else
          Rails.logger.info "Doing full sync to ensure completeness"
          # Keep the original oldest_commit_date to sync everything
        end
      else
        Rails.logger.info "No existing commits found, starting fresh sync"
      end
      
      # Process commits in monthly batches, from newest to oldest
      # Add a day buffer to ensure we catch commits on the exact dates
      current_date = newest_commit_date + 1.day
      
      while current_date >= oldest_commit_date
        # Check for timeout
        if Time.now - start_time > timeout_duration
          Rails.logger.warn "Incremental sync timeout for #{full_name} after processing #{total_processed} commits"
          
          # Save progress if we processed any commits
          if latest_sha
            update_columns(
              last_synced_commit: latest_sha,
              last_synced_at: Time.current
            )
          end
          
          return :timeout
        end
        
        # Define the date range for this batch (1 month)
        since_date = current_date - 1.month
        until_date = current_date
        
        # Make sure we don't go before the oldest commit
        since_date = [since_date, oldest_commit_date - 1.day].max
        
        Rails.logger.info "Fetching commits from #{since_date} to #{until_date} for #{full_name}"
        
        # Fetch commits for this time period
        batch = fetch_commits_by_date_range(dir, since_date, until_date)
        
        Rails.logger.info "Found #{batch.size} commits in this batch"
        
        if batch.any?
          # Track the latest commit SHA from first batch
          latest_sha ||= batch.first[:sha]
          
          # Clean and insert batch
          cleaned_batch = batch.map do |commit|
            commit.transform_values do |value|
              if value.is_a?(String)
                value.gsub("\u0000", '')
              else
                value
              end
            end
          end
          
          cleaned_batch.each_slice(1000) do |chunk|
            # Use unique_by to handle duplicates properly
            Commit.upsert_all(
              chunk, 
              unique_by: [:repository_id, :sha],
              returning: false
            )
          end
          
          total_processed += batch.size
          Rails.logger.info "Processed #{batch.size} commits from #{since_date.to_date} to #{until_date.to_date} for #{full_name}"
        end
        
        # Move to the previous month
        current_date = since_date
      end
      
      # Update tracking info
      if latest_sha
        update_columns(
          last_synced_commit: latest_sha,
          last_synced_at: Time.current
        )
      end
      
      Rails.logger.info "Successfully synced #{total_processed} commits for #{full_name}"
      total_processed
    end
  rescue => e
    Rails.logger.error "Error in incremental sync for #{full_name}: #{e.message}"
    raise SyncError, "Failed to sync commits incrementally for #{full_name}: #{e.message}"
  end
  
  def get_oldest_commit_date(dir)
    # Use head -1 instead of -n 1 because --reverse with -n 1 doesn't work properly
    output = `git -C #{dir.shellescape} log --reverse --format=%aI 2>&1 | head -1`.strip
    
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
    output = `git -C #{dir.shellescape} log --format=%aI -n 1 2>&1`.strip
    
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
  
  def fetch_commits_by_date_range(dir, since_date, until_date)
    format = "%H|%s|%aI|%an|%ae|%cn|%ce|%P"
    
    # Use ISO8601 format for date handling (git understands this better)
    git_cmd = [
      "git", "-C", dir, "log",
      "--format=#{format}",
      "--numstat", "-z",
      "--since=#{since_date.iso8601}",
      "--until=#{until_date.iso8601}",
      "--all"  # Search all branches, not just HEAD
    ]
    
    output = `#{git_cmd.shelljoin} 2>&1`
    
    # Log if there's an error
    if $?.exitstatus != 0
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
    
    output.split("\0").each do |commit_block|
      next if commit_block.empty?
      
      lines = commit_block.lines
      next if lines.empty?
      
      header = lines.shift
      parts = header.split('|', 8)
      next unless parts.length == 8
      
      sha, message, timestamp, author_name, author_email, committer_name, committer_email, parents = parts
      
      additions = 0
      deletions = 0  
      files = 0
      
      lines.each do |line|
        if match = line.match(/^(\d+|-)\t(\d+|-)\t/)
          add = match[1] == '-' ? 0 : match[1].to_i
          del = match[2] == '-' ? 0 : match[2].to_i
          additions += add
          deletions += del
          files += 1
        end
      end
      
      commits << {
        repository_id: repo_id,
        sha: sha,
        message: message.strip.gsub("\u0000", ''),
        timestamp: timestamp,
        merge: parents.include?(' '),
        author: "#{author_name} <#{author_email}>".gsub("\u0000", ''),
        committer: "#{committer_name} <#{committer_email}>".gsub("\u0000", ''),
        stats: [additions, deletions, files]
      }
    end
    
    commits
  end
  
  def sync_commits_streaming
    Timeout.timeout(900) do
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
          returning: false,
          record_timestamps: false
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
    Rails.logger.error "Sync commits streaming timeout for #{full_name} after 15 minutes"
    raise TimeoutError, "Sync commits streaming timed out for #{full_name} after 15 minutes"
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
