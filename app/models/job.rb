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
      Timeout.timeout(900) do
        results = parse_commits
        update!(results: results, status: 'complete')
      end
    rescue Timeout::Error => e
      Rails.logger.error "Job #{id} timeout after 15 minutes for URL: #{url}"
      update(results: {error: "Timeout after 15 minutes"}, status: 'error')
    rescue => e
      update(results: {error: e.inspect}, status: 'error')
    end
  end

  def parse_commits
    repo = Repository.find_or_create_from_url(url)
    return nil unless repo
    
    repo.count_commits
    repo.as_json
  end
end
