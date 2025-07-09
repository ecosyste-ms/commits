class SyncCommitsWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options queue: 'high_priority', retry: 3

  def perform(repository_id)
    repository = Repository.find_by_id(repository_id)
    return unless repository

    repository.sync_details
    repository.sync_commits
    repository.count_commits
  end
end