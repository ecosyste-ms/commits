require "test_helper"

class RepositoryTimeoutTest < ActiveSupport::TestCase
  def setup
    @host = Host.create!(name: "github.com", url: "https://github.com", kind: "github")
    @repository = Repository.create!(
      host: @host,
      full_name: "test/repo",
      owner: "test"
    )
  end

  test "sync_commits handles timeout properly" do
    # Mock fetch_commits to raise timeout
    @repository.stubs(:fetch_commits).raises(Timeout::Error)
    Rails.logger.expects(:error).with("Sync commits timeout for test/repo after 15 minutes")
    
    assert_raises(Timeout::Error) do
      @repository.sync_commits
    end
  end

  test "sync_commits completes successfully within timeout" do
    test_commits = [
      {
        repository_id: @repository.id,
        sha: "abc123",
        message: "Test commit",
        timestamp: Time.now.iso8601,
        merge: false,
        author: "Test Author <test@example.com>",
        committer: "Test Committer <test@example.com>",
        stats: [1, 1, 2]
      }
    ]
    
    @repository.stubs(:fetch_commits).returns(test_commits)
    
    assert_nothing_raised do
      @repository.sync_commits
    end
  end

  test "sync_commits logs error message on timeout" do
    @repository.stubs(:fetch_commits).raises(Timeout::Error)
    Rails.logger.expects(:error).with("Sync commits timeout for test/repo after 15 minutes")
    
    assert_raises(Timeout::Error) do
      @repository.sync_commits
    end
  end
end