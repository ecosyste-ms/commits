require 'test_helper'

class SyncRepositoryWorkerTest < ActiveSupport::TestCase
  test 'allows transient clone errors to reach Sidekiq' do
    repository = create(:repository)
    Repository.expects(:find_by_id).with(repository.id).returns(repository)
    repository.expects(:sync_all).raises(
      Repository::TransientCloneError,
      'Failed to clone owner/repository: HTTP 401'
    )

    assert_raises(Repository::TransientCloneError) do
      SyncRepositoryWorker.new.perform(repository.id)
    end
  end
end
