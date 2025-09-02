require "test_helper"

class SyncCommitsWorkerTest < ActiveSupport::TestCase
  def setup
    @host = Host.create!(name: "github.com", url: "https://github.com", kind: "github")
    @repository = Repository.create!(
      host: @host,
      full_name: "test/repo",
      owner: "test"
    )
    Sidekiq::Testing.fake!
  end

  test "enqueues three separate jobs when performed with default priority" do
    SyncDetailsWorker.jobs.clear
    SyncCommitsDataWorker.jobs.clear
    CountCommitsWorker.jobs.clear

    SyncCommitsWorker.new.perform(@repository.id)

    assert_equal 1, SyncDetailsWorker.jobs.size
    assert_equal 1, SyncCommitsDataWorker.jobs.size
    assert_equal 1, CountCommitsWorker.jobs.size

    # Check that jobs have the correct arguments (repository_id and high_priority=false by default)
    assert_equal [@repository.id, false], SyncDetailsWorker.jobs.first['args']
    assert_equal [@repository.id, false], SyncCommitsDataWorker.jobs.first['args']
    assert_equal [@repository.id, false], CountCommitsWorker.jobs.first['args']
  end

  test "enqueues three separate jobs with high priority when specified" do
    SyncDetailsWorker.jobs.clear
    SyncCommitsDataWorker.jobs.clear
    CountCommitsWorker.jobs.clear

    SyncCommitsWorker.new.perform(@repository.id, true)

    assert_equal 1, SyncDetailsWorker.jobs.size
    assert_equal 1, SyncCommitsDataWorker.jobs.size
    assert_equal 1, CountCommitsWorker.jobs.size

    # Check that jobs have the correct arguments (repository_id and high_priority=true)
    assert_equal [@repository.id, true], SyncDetailsWorker.jobs.first['args']
    assert_equal [@repository.id, true], SyncCommitsDataWorker.jobs.first['args']
    assert_equal [@repository.id, true], CountCommitsWorker.jobs.first['args']
  end

  test "returns early if repository not found" do
    SyncDetailsWorker.jobs.clear
    SyncCommitsDataWorker.jobs.clear
    CountCommitsWorker.jobs.clear

    SyncCommitsWorker.new.perform(999999)

    assert_equal 0, SyncDetailsWorker.jobs.size
    assert_equal 0, SyncCommitsDataWorker.jobs.size
    assert_equal 0, CountCommitsWorker.jobs.size
  end

  test "enqueues jobs to correct priority queues" do
    SyncDetailsWorker.jobs.clear
    SyncCommitsDataWorker.jobs.clear
    CountCommitsWorker.jobs.clear

    # Test with high priority
    SyncCommitsWorker.new.perform(@repository.id, true)

    assert_equal 'sync_details_high_priority', SyncDetailsWorker.jobs.first['queue']
    assert_equal 'sync_commits_data_high_priority', SyncCommitsDataWorker.jobs.first['queue']
    assert_equal 'count_commits_high_priority', CountCommitsWorker.jobs.first['queue']

    SyncDetailsWorker.jobs.clear
    SyncCommitsDataWorker.jobs.clear
    CountCommitsWorker.jobs.clear

    # Test with normal priority
    SyncCommitsWorker.new.perform(@repository.id, false)

    assert_equal 'sync_details', SyncDetailsWorker.jobs.first['queue']
    assert_equal 'sync_commits_data', SyncCommitsDataWorker.jobs.first['queue']
    assert_equal 'count_commits', CountCommitsWorker.jobs.first['queue']
  end

  test "perform_async enqueues to correct queue based on priority" do
    Sidekiq::Client.expects(:push).with(
      'class' => SyncCommitsWorker,
      'queue' => 'default',
      'args' => [@repository.id, false]
    )
    
    SyncCommitsWorker.perform_async(@repository.id)

    Sidekiq::Client.expects(:push).with(
      'class' => SyncCommitsWorker,
      'queue' => 'high_priority',
      'args' => [@repository.id, true]
    )
    
    SyncCommitsWorker.perform_async(@repository.id, true)
  end
end