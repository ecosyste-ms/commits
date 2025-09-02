class Host < ApplicationRecord
  has_many :repositories
  has_many :committers

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :url, presence: true
  validates :kind, presence: true

  scope :visible, -> { where('repositories_count > 0 AND commits_count > 0') }
  scope :indexable, -> { where(online: true, can_crawl_api: true) }

  def self.find_by_domain(domain)
    Host.all.find { |host| host.domain == domain }
  end

  def to_s
    name
  end

  def to_param
    name
  end

  def domain
    Addressable::URI.parse(url).host
  end

  def display_kind?
    return false if name.split('.').length == 2 && name.split('.').first.downcase == kind
    name.downcase != kind
  end

  def online?
    online
  end

  def can_be_indexed?
    online? && can_crawl_api?
  end

  def status_display
    return 'Online' if online?
    return 'Offline' unless online?
    status&.humanize || 'Unknown'
  end

  def sync_repository_async(full_name, remote_ip = '0.0.0.0')
    repo = Repository.find_or_create_from_host(self, full_name)
    
    job = Job.new(url: repo.html_url, status: 'pending', ip: remote_ip)
    if job.save
      job.parse_commits_async
    end
    job
  end

  def sync_recently_updated_repositories_async
    return nil unless can_be_indexed?
    
    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
      f.headers['User-Agent'] = 'commits.ecosyste.ms'
    end
    
    response = conn.get('/api/v1/hosts/' + name + '/repositories')
    return nil unless response.success?
    json = response.body

    json.each do |repo|
      puts "syncing #{repo['full_name']}"
      sync_repository_async(repo['full_name'])
    end
  end 

  def self.update_counts
    Host.all.each(&:update_counts)
  end

  def update_counts
    self.repositories_count = repositories.visible.count
    self.commits_count = repositories.visible.sum(:total_commits)
    self.contributors_count = repositories.visible.sum(:total_committers)
    self.owners_count = repositories.visible.count('distinct owner')
    save
  end

  def self.sync_all
    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
      f.headers['User-Agent'] = 'commits.ecosyste.ms'
    end
    
    response = conn.get('/api/v1/hosts')
    return nil unless response.success?
    json = response.body

    json.each do |host|
      Host.find_or_create_by(name: host['name']).tap do |r|
        r.url = host['url']
        r.kind = host['kind']
        r.icon_url = host['icon_url']
        r.status = host['status']
        r.online = host['online']
        r.status_checked_at = host['status_checked_at'] ? Time.parse(host['status_checked_at']) : nil
        r.response_time = host['response_time']
        r.last_error = host['last_error']
        r.can_crawl_api = host['can_crawl_api']
        r.host_url = host['host_url']
        r.repositories_url = host['repositories_url']
        r.owners_url = host['owners_url']
        r.last_synced_at = Time.now
        r.save
      end
    end
  end
end
