require "test_helper"

class CountCommitsWorkerTest < ActiveSupport::TestCase
  def setup
    @host = Host.create!(name: "github.com", url: "https://github.com", kind: "github")
    @repository = Repository.create!(
      host: @host,
      full_name: "test/repo",
      owner: "test"
    )
  end

  test "calls count_commits on repository" do
    # Mock the count_commits method to avoid actual git operations
    Repository.any_instance.expects(:count_commits)
    
    CountCommitsWorker.new.perform(@repository.id)
  end

  test "returns early if repository not found" do
    Repository.expects(:find_by_id).with(999999).returns(nil)
    
    assert_nothing_raised do
      CountCommitsWorker.new.perform(999999)
    end
  end

  test "perform_async enqueues to regular queue by default" do
    Sidekiq::Client.expects(:push).with(
      'class' => CountCommitsWorker,
      'queue' => 'count_commits',
      'args' => [@repository.id, false]
    )
    
    CountCommitsWorker.perform_async(@repository.id)
  end

  test "perform_async enqueues to high priority queue when specified" do
    Sidekiq::Client.expects(:push).with(
      'class' => CountCommitsWorker,
      'queue' => 'count_commits_high_priority',
      'args' => [@repository.id, true]
    )
    
    CountCommitsWorker.perform_async(@repository.id, true)
  end
end