require "test_helper"
require "tmpdir"

class RepositoryTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:host)
    should have_many(:commits)
  end

  context 'validations' do
    should validate_presence_of(:full_name)
  end

  def setup
    @host = Host.create!(name: "github.com", url: "https://github.com", kind: "github")
    @repository = Repository.create!(
      host: @host,
      full_name: "test/repo",
      owner: "test"
    )
  end

  # Timeout tests
  test "sync_commits handles timeout properly" do
    @repository.stubs(:fetch_commits).raises(Timeout::Error)
    Rails.logger.expects(:error).with("Sync commits timeout for test/repo after 15 minutes")
    
    assert_raises(Repository::TimeoutError) do
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
    
    assert_raises(Repository::TimeoutError) do
      @repository.sync_commits
    end
  end

  test "sync_commits handles UTF-8 encoding issues" do
    # Create commits with null bytes (which our code should clean)
    test_commits = [
      {
        repository_id: @repository.id,
        sha: "abc123",
        message: "Test commit with null \u0000 chars",
        timestamp: Time.now.iso8601,
        merge: false,
        author: "Test Author\u0000 <test@example.com>",
        committer: "Test Committer <test@example.com>",
        stats: [1, 1, 2]
      },
      {
        repository_id: @repository.id,
        sha: "def456",
        message: "Normal commit",
        timestamp: Time.now.iso8601,
        merge: false,
        author: "Normal Author <normal@example.com>",
        committer: "Normal Committer <normal@example.com>",
        stats: [2, 3, 1]
      }
    ]
    
    @repository.stubs(:fetch_commits).returns(test_commits)
    
    # Should not raise encoding errors
    assert_nothing_raised do
      @repository.sync_commits
    end
    
    # Verify commits were inserted
    assert_equal "abc123", @repository.reload.last_synced_commit
  end

  test "sync_commits handles general errors with proper logging" do
    error_message = "Some database error"
    @repository.stubs(:fetch_commits).raises(StandardError.new(error_message))
    Rails.logger.expects(:error).with("Error syncing commits for test/repo: #{error_message}")
    
    assert_raises(Repository::SyncError) do
      @repository.sync_commits
    end
  end

  test "sync_commits updates last_synced_commit after successful sync" do
    test_commits = [
      {
        repository_id: @repository.id,
        sha: "latest123",
        message: "Latest commit",
        timestamp: Time.now.iso8601,
        merge: false,
        author: "Test Author <test@example.com>",
        committer: "Test Committer <test@example.com>",
        stats: [1, 1, 1]
      },
      {
        repository_id: @repository.id,
        sha: "older456",
        message: "Older commit",
        timestamp: 1.day.ago.iso8601,
        merge: false,
        author: "Test Author <test@example.com>",
        committer: "Test Committer <test@example.com>",
        stats: [2, 2, 2]
      }
    ]
    
    @repository.stubs(:fetch_commits).returns(test_commits)
    
    @repository.sync_commits
    
    assert_equal "latest123", @repository.reload.last_synced_commit
  end

  test "sync_commits handles empty commit list" do
    @repository.stubs(:fetch_commits).returns([])
    
    assert_nothing_raised do
      @repository.sync_commits
    end
    
    # Should not update last_synced_commit when no commits
    assert_nil @repository.reload.last_synced_commit
  end

  test "sync_commits batches large commit lists" do
    # Create 2500 test commits to test batching (batch size is 1000)
    test_commits = (1..2500).map do |i|
      {
        repository_id: @repository.id,
        sha: "sha#{i}",
        message: "Commit #{i}",
        timestamp: Time.now.iso8601,
        merge: false,
        author: "Author #{i} <author#{i}@example.com>",
        committer: "Committer #{i} <committer#{i}@example.com>",
        stats: [i, i, i]
      }
    end
    
    @repository.stubs(:fetch_commits).returns(test_commits)
    
    # Expect upsert_all to be called 3 times (2500/1000 = 2.5, so 3 batches)
    Commit.expects(:upsert_all).times(3)
    
    @repository.sync_commits
  end

  # Git log tests
  test "fetch_commits_internal parses git log output correctly" do
    Dir.mktmpdir do |dir|
      # Create a test git repository
      `git init #{dir} 2>&1`
      
      # Create some test commits
      File.write("#{dir}/file1.txt", "content1")
      `cd #{dir} && git add file1.txt && git -c user.name="Test User" -c user.email="test@example.com" commit -m "First commit" 2>&1`
      
      File.write("#{dir}/file2.txt", "content2")
      `cd #{dir} && git add file2.txt && git -c user.name="Another User" -c user.email="another@example.com" commit -m "Second commit" 2>&1`
      
      # Test fetch_commits_internal
      commits = @repository.fetch_commits_internal(dir)
      
      assert_equal 2, commits.length
      
      # Check the most recent commit (second commit)
      latest_commit = commits.first
      assert_equal @repository.id, latest_commit[:repository_id]
      assert_match /^[a-f0-9]{40}$/, latest_commit[:sha]
      assert_equal "Second commit", latest_commit[:message]
      assert_equal "Another User <another@example.com>", latest_commit[:author]
      assert_equal false, latest_commit[:merge]
      assert_kind_of Array, latest_commit[:stats]
      assert_equal 3, latest_commit[:stats].length
      
      # Check the first commit
      first_commit = commits.last
      assert_equal "First commit", first_commit[:message]
      assert_equal "Test User <test@example.com>", first_commit[:author]
    end
  end

  test "fetch_commits_internal handles merge commits" do
    Dir.mktmpdir do |dir|
      # Create a test git repository with a merge commit
      `git init #{dir} 2>&1`
      
      # Create initial commit
      File.write("#{dir}/file1.txt", "content1")
      `cd #{dir} && git add file1.txt && git -c user.name="Test User" -c user.email="test@example.com" commit -m "Initial commit" 2>&1`
      
      # Create a branch and add a commit
      `cd #{dir} && git checkout -b feature 2>&1`
      File.write("#{dir}/feature.txt", "feature content")
      `cd #{dir} && git add feature.txt && git -c user.name="Test User" -c user.email="test@example.com" commit -m "Feature commit" 2>&1`
      
      # Go back to main and add another commit
      `cd #{dir} && git checkout main 2>&1`
      File.write("#{dir}/main.txt", "main content")
      `cd #{dir} && git add main.txt && git -c user.name="Test User" -c user.email="test@example.com" commit -m "Main commit" 2>&1`
      
      # Merge the feature branch
      `cd #{dir} && git -c user.name="Test User" -c user.email="test@example.com" merge feature --no-ff -m "Merge feature branch" 2>&1`
      
      commits = @repository.fetch_commits_internal(dir)
      
      # Find the merge commit (should be the most recent)
      merge_commit = commits.first
      assert_equal true, merge_commit[:merge], "Should detect merge commit"
      assert_equal "Merge feature branch", merge_commit[:message]
    end
  end

  test "fetch_commits_internal respects last_synced_commit" do
    Dir.mktmpdir do |dir|
      # Create a test git repository
      `git init #{dir} 2>&1`
      
      # Create first commit
      File.write("#{dir}/file1.txt", "content1")
      `cd #{dir} && git add file1.txt && git -c user.name="Test User" -c user.email="test@example.com" commit -m "First commit" 2>&1`
      first_sha = `cd #{dir} && git rev-parse HEAD`.strip
      
      # Create second commit
      File.write("#{dir}/file2.txt", "content2")
      `cd #{dir} && git add file2.txt && git -c user.name="Test User" -c user.email="test@example.com" commit -m "Second commit" 2>&1`
      
      # Set last_synced_commit to the first commit
      @repository.update(last_synced_commit: first_sha, total_commits: 1)
      
      commits = @repository.fetch_commits_internal(dir)
      
      # Should only get the second commit
      assert_equal 1, commits.length
      assert_equal "Second commit", commits.first[:message]
    end
  end

  test "fetch_commits_internal handles empty repository" do
    Dir.mktmpdir do |dir|
      # Create an empty git repository
      `git init #{dir} 2>&1`
      
      commits = @repository.fetch_commits_internal(dir)
      
      assert_equal 0, commits.length
    end
  end

  # Class method tests
  test "find_or_create_from_host finds existing repository" do
    existing_repo = @host.repositories.create!(full_name: "existing/repo")
    
    found_repo = Repository.find_or_create_from_host(@host, "existing/repo")
    
    assert_equal existing_repo.id, found_repo.id
    assert_equal "existing/repo", found_repo.full_name
  end

  test "find_or_create_from_host creates new repository when not found" do
    assert_difference 'Repository.count', 1 do
      new_repo = Repository.find_or_create_from_host(@host, "new/repo")
      
      assert_equal "new/repo", new_repo.full_name
      assert_equal @host.id, new_repo.host_id
    end
  end

  test "find_or_create_from_host is case insensitive" do
    existing_repo = @host.repositories.create!(full_name: "CaseSensitive/Repo")
    
    found_repo = Repository.find_or_create_from_host(@host, "casesensitive/repo")
    
    assert_equal existing_repo.id, found_repo.id
  end

  test "find_or_create_from_url finds repository from URL" do
    existing_repo = @host.repositories.create!(full_name: "owner/repo")
    
    found_repo = Repository.find_or_create_from_url("https://github.com/owner/repo")
    
    assert_equal existing_repo.id, found_repo.id
  end

  test "find_or_create_from_url strips .git suffix" do
    existing_repo = @host.repositories.create!(full_name: "owner/repo")
    
    found_repo = Repository.find_or_create_from_url("https://github.com/owner/repo.git")
    
    assert_equal existing_repo.id, found_repo.id
  end

  test "find_or_create_from_url returns nil for unknown host" do
    repo = Repository.find_or_create_from_url("https://unknown-host.com/owner/repo")
    
    assert_nil repo
  end

  test "find_or_create_from_url falls back to external API" do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/new/repo")
      .to_return(status: 200, body: {
        host: { name: "github.com" },
        full_name: "new/repo"
      }.to_json, headers: {'Content-Type' => 'application/json'})
    
    assert_difference 'Repository.count', 1 do
      repo = Repository.find_or_create_from_url("https://github.com/new/repo")
      
      assert_equal "new/repo", repo.full_name
      assert_equal @host.id, repo.host_id
    end
  end
end
