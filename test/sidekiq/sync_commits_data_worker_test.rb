require "test_helper"

class SyncCommitsDataWorkerTest < ActiveSupport::TestCase
  def setup
    @host = Host.create!(name: "github.com", url: "https://github.com", kind: "github")
    @repository = Repository.create!(
      host: @host,
      full_name: "test/repo",
      owner: "test"
    )
  end

  test "calls sync_commits on repository" do
    # Mock the sync_commits method to avoid actual git operations
    Repository.any_instance.expects(:sync_commits)
    
    SyncCommitsDataWorker.new.perform(@repository.id)
  end

  test "returns early if repository not found" do
    Repository.expects(:find_by_id).with(999999).returns(nil)
    
    assert_nothing_raised do
      SyncCommitsDataWorker.new.perform(999999)
    end
  end

  test "perform_async enqueues to regular queue by default" do
    Sidekiq::Client.expects(:push).with(
      'class' => SyncCommitsDataWorker,
      'queue' => 'sync_commits_data',
      'args' => [@repository.id, false]
    )
    
    SyncCommitsDataWorker.perform_async(@repository.id)
  end

  test "perform_async enqueues to high priority queue when specified" do
    Sidekiq::Client.expects(:push).with(
      'class' => SyncCommitsDataWorker,
      'queue' => 'sync_commits_data_high_priority',
      'args' => [@repository.id, true]
    )
    
    SyncCommitsDataWorker.perform_async(@repository.id, true)
  end
end