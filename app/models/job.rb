class Job < ApplicationRecord
  validates_presence_of :url
  validates_uniqueness_of :id

  scope :status, ->(status) { where(status: status) }

  def self.check_statuses
    Job.where(status: ["queued", "working"]).find_each(&:check_status)
  end

  def self.clean_up
    Job.status(["complete",'error']).where('created_at < ?', 1.day.ago).in_batches(of: 1000).delete_all
    Job.where('created_at < ?', 1.week.ago).in_batches(of: 1000).delete_all
  end

  def check_status
    return if sidekiq_id.blank?
    return if finished?
    update(status: fetch_status)
  end

  def fetch_status
    Sidekiq::Status.status(sidekiq_id).presence || 'pending'
  end

  def in_progress?
    ['pending','queued', 'working'].include?(status)
  end

  def finished?
    ['complete', 'error'].include?(status)
  end

  def parse_commits_async
    sidekiq_id = ParseCommitsWorker.perform_async(id)
    update(sidekiq_id: sidekiq_id)
  end

  def perform_commit_parsing
    begin
      results = parse_commits
      update!(results: results, status: 'complete')      
    rescue => e
      update(results: {error: e.inspect}, status: 'error')
    end
  end

  def parse_commits
    # find repo from repos service
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
    repo = host.repositories.find_by('lower(full_name) = ?', json['full_name'].downcase)
    repo = host.repositories.create(full_name: json['full_name']) if repo.nil?
    
    repo.count_commits
    
    results = repo.as_json
    return results
  end
end
