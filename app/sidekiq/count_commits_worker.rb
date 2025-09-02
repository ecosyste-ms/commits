class CountCommitsWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options retry: 3

  def perform(repository_id, high_priority = false)
    repository = Repository.find_by_id(repository_id)
    return unless repository

    repository.count_commits
  end

  def self.perform_async(*args)
    repository_id = args[0]
    high_priority = args[1] || false
    queue = high_priority ? 'count_commits_high_priority' : 'count_commits'
    Sidekiq::Client.push('class' => self, 'queue' => queue, 'args' => [repository_id, high_priority])
  end
end