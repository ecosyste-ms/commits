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
    Rails.logger.expects(:error).with("Sync commits timeout for test/repo after 5 minutes")
    
    assert_raises(Repository::TimeoutError) do
      @repository.sync_commits(incremental: false)
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
      @repository.sync_commits(incremental: false)
    end
  end

  test "sync_commits logs error message on timeout" do
    @repository.stubs(:fetch_commits).raises(Timeout::Error)
    Rails.logger.expects(:error).with("Sync commits timeout for test/repo after 5 minutes")
    
    assert_raises(Repository::TimeoutError) do
      @repository.sync_commits(incremental: false)
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
      @repository.sync_commits(incremental: false)
    end
    
    # Verify commits were inserted
    assert_equal "abc123", @repository.reload.last_synced_commit
  end

  test "sync_commits handles general errors with proper logging" do
    error_message = "Some database error"
    @repository.stubs(:fetch_commits).raises(StandardError.new(error_message))
    Rails.logger.expects(:error).with("Error syncing commits for test/repo: #{error_message}")
    
    assert_raises(Repository::SyncError) do
      @repository.sync_commits(incremental: false)
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
    
    @repository.sync_commits(incremental: false)
    
    assert_equal "latest123", @repository.reload.last_synced_commit
  end

  test "sync_commits handles empty commit list" do
    @repository.stubs(:fetch_commits).returns([])
    
    assert_nothing_raised do
      @repository.sync_commits(incremental: false)
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
    
    @repository.sync_commits(incremental: false)
  end
  
  test "sync_commits_incremental returns count of processed commits" do
    # This is a simple integration test using mocks
    @repository.stubs(:clone_repository)
    @repository.stubs(:get_oldest_commit_date).returns(2.months.ago)
    @repository.stubs(:get_newest_commit_date).returns(Time.now)
    
    # Mock fetch_commits_by_date_range to return some commits only for the first call
    # then empty arrays for subsequent calls (since we process multiple months)
    commits_batch = [
      { repository_id: @repository.id, sha: "abc123", message: "Test", timestamp: Time.now.iso8601,
        merge: false, author: "Test <test@test.com>", committer: "Test <test@test.com>", stats: [1,1,1] }
    ]
    @repository.stubs(:fetch_commits_by_date_range).returns(commits_batch, [], [])
    
    # Stub the git rev-parse HEAD command (matches both -C and --git-dir formats)
    @repository.stubs(:`).with { |cmd| cmd.include?("rev-parse HEAD") }.returns("abc123\n")
    
    result = @repository.sync_commits_incremental
    
    # Should return the count
    assert_equal 1, result
  end
  
  test "sync_commits_incremental processes this repository's commits" do
    # Use this very repository as test data
    repo_path = Rails.root.to_s
    
    # Update repository to point to this project
    @repository.update(full_name: "ecosystems/commits")
    @repository.stubs(:git_clone_url).returns(repo_path)
    @repository.stubs(:clone_repository).with(anything) do |dir|
      # Instead of cloning, just copy .git to the temp dir
      `cp -r #{repo_path}/.git #{dir}/`
    end
    
    # Run incremental sync
    result = @repository.sync_commits_incremental
    
    # Should have processed some commits (this repo has hundreds)
    assert result > 0, "Should have processed at least some commits"
    
    # Check that commits were actually saved
    assert_equal result, @repository.commits.count
    
    # Verify we got actual commits from this repo
    commit_messages = @repository.commits.pluck(:message)
    
    # Check for some known commits (from earlier in our session)
    assert commit_messages.any? { |m| m.include?("UTF-8") || m.include?("encoding") }, 
           "Should have commits about UTF-8 fixes we made"
  end
  
  test "sync_commits_incremental can resume from previous sync" do
    # Use this repository as test data
    repo_path = Rails.root.to_s
    
    @repository.update(full_name: "ecosystems/commits")
    @repository.stubs(:git_clone_url).returns(repo_path)
    @repository.stubs(:clone_repository).with(anything) do |dir|
      `cp -r #{repo_path}/.git #{dir}/`
    end
    
    # First sync - process all commits
    first_count = @repository.sync_commits_incremental
    assert first_count > 0
    
    # Second sync - should not duplicate commits
    second_count = @repository.sync_commits_incremental
    
    # Should still have the same number of commits (no duplicates)
    assert_equal first_count, @repository.commits.count
    
    # The second sync might process the same commits but upsert prevents duplicates
    # or it might detect we're up to date and process 0 new commits
    assert second_count >= 0
  end
  
  test "sync_commits_incremental processes commits in monthly batches" do
    # Mock the methods instead of using real git repos
    @repository.stubs(:clone_repository)
    
    # Mock date range
    oldest = 3.months.ago
    newest = Time.now
    @repository.stubs(:get_oldest_commit_date).returns(oldest)
    @repository.stubs(:get_newest_commit_date).returns(newest)
    
    # Create mock commits for different date ranges
    batch1 = [
      { repository_id: @repository.id, sha: "sha1", message: "msg1", timestamp: 1.week.ago.iso8601, 
        merge: false, author: "A <a@a.com>", committer: "C <c@c.com>", stats: [1,1,1] }
    ]
    batch2 = [
      { repository_id: @repository.id, sha: "sha2", message: "msg2", timestamp: 1.month.ago.iso8601,
        merge: false, author: "A <a@a.com>", committer: "C <c@c.com>", stats: [1,1,1] }
    ]
    batch3 = [
      { repository_id: @repository.id, sha: "sha3", message: "msg3", timestamp: 2.months.ago.iso8601,
        merge: false, author: "A <a@a.com>", committer: "C <c@c.com>", stats: [1,1,1] }
    ]
    batch4 = [
      { repository_id: @repository.id, sha: "sha4", message: "msg4", timestamp: 3.months.ago.iso8601,
        merge: false, author: "A <a@a.com>", committer: "C <c@c.com>", stats: [1,1,1] }
    ]
    
    # Stub fetch_commits_by_date_range to return appropriate batches
    @repository.stubs(:fetch_commits_by_date_range).returns(batch4, batch3, batch2, batch1)
    
    # Stub the git rev-parse HEAD command (matches both -C and --git-dir formats)
    @repository.stubs(:`).with { |cmd| cmd.include?("rev-parse HEAD") }.returns("sha1\n")
    
    # Stub Commit.upsert_all
    Commit.stubs(:upsert_all)
    
    # Run incremental sync
    result = @repository.sync_commits_incremental
    
    # Should have processed all 4 commits
    assert_equal 4, result
  end
  
  test "sync_commits_incremental handles timeout gracefully" do
    # Mock the methods
    @repository.stubs(:clone_repository)
    
    # Mock date range
    oldest = 3.months.ago
    newest = Time.now
    @repository.stubs(:get_oldest_commit_date).returns(oldest)
    @repository.stubs(:get_newest_commit_date).returns(newest)
    
    # Create a batch of commits
    batch = [
      { repository_id: @repository.id, sha: "sha1", message: "msg1", timestamp: 1.week.ago.iso8601, 
        merge: false, author: "A <a@a.com>", committer: "C <c@c.com>", stats: [1,1,1] }
    ]
    
    @repository.stubs(:fetch_commits_by_date_range).returns(batch)
    
    # Stub Time.now to simulate timeout after first batch
    current_time = Time.now
    Time.stubs(:now).returns(current_time, current_time + 6.minutes)
    
    # Stub the git rev-parse HEAD command (called when timeout occurs)
    @repository.stubs(:`).with { |cmd| cmd.include?("rev-parse HEAD") }.returns("sha1\n")
    
    # Stub Commit.upsert_all to avoid database operations
    Commit.stubs(:upsert_all)
    
    # Run incremental sync
    result = @repository.sync_commits_incremental
    
    # Should return :timeout
    assert_equal :timeout, result
  end
  
  test "sync_commits with incremental mode makes progress on timeout" do
    @repository.stubs(:sync_commits_incremental).returns(:timeout)
    Rails.logger.expects(:info).with("Incremental sync made partial progress for test/repo")
    
    result = @repository.sync_commits(incremental: true)
    
    assert_equal true, result
  end

  # Incremental sync helper tests
  test "get_oldest_commit_date returns correct date" do
    Dir.mktmpdir do |dir|
      # Create a test git repository
      `git init #{dir} 2>&1`
      
      # Create commits with known dates
      File.write("#{dir}/file1.txt", "content1")
      `cd #{dir} && git add . && GIT_AUTHOR_DATE="2020-01-01T10:00:00Z" GIT_COMMITTER_DATE="2020-01-01T10:00:00Z" git -c user.name="Test" -c user.email="test@test.com" commit -m "First" 2>&1`
      
      File.write("#{dir}/file2.txt", "content2")
      `cd #{dir} && git add . && GIT_AUTHOR_DATE="2020-06-01T10:00:00Z" GIT_COMMITTER_DATE="2020-06-01T10:00:00Z" git -c user.name="Test" -c user.email="test@test.com" commit -m "Second" 2>&1`
      
      oldest = @repository.get_oldest_commit_date(dir)
      
      assert_not_nil oldest
      assert_equal Time.parse("2020-01-01T10:00:00Z"), oldest
    end
  end
  
  test "get_newest_commit_date returns correct date" do
    Dir.mktmpdir do |dir|
      # Create a test git repository
      `git init #{dir} 2>&1`
      
      # Create commits with known dates
      File.write("#{dir}/file1.txt", "content1")
      `cd #{dir} && git add . && GIT_AUTHOR_DATE="2020-01-01T10:00:00Z" GIT_COMMITTER_DATE="2020-01-01T10:00:00Z" git -c user.name="Test" -c user.email="test@test.com" commit -m "First" 2>&1`
      
      File.write("#{dir}/file2.txt", "content2")
      `cd #{dir} && git add . && GIT_AUTHOR_DATE="2020-06-01T10:00:00Z" GIT_COMMITTER_DATE="2020-06-01T10:00:00Z" git -c user.name="Test" -c user.email="test@test.com" commit -m "Second" 2>&1`
      
      newest = @repository.get_newest_commit_date(dir)
      
      assert_not_nil newest
      assert_equal Time.parse("2020-06-01T10:00:00Z"), newest
    end
  end
  
  test "fetch_commits_by_date_range returns commits in range" do
    Dir.mktmpdir do |dir|
      # Create a test git repository
      `git init #{dir} 2>&1`
      
      # Create commits across different dates
      dates = [
        "2020-01-01T10:00:00Z",
        "2020-02-01T10:00:00Z", 
        "2020-03-01T10:00:00Z",
        "2020-04-01T10:00:00Z"
      ]
      
      dates.each_with_index do |date, i|
        File.write("#{dir}/file#{i}.txt", "content#{i}")
        `cd #{dir} && git add . && GIT_AUTHOR_DATE="#{date}" GIT_COMMITTER_DATE="#{date}" git -c user.name="Test" -c user.email="test@test.com" commit -m "Commit #{i}" 2>&1`
      end
      
      # Fetch commits from Feb to March (should get 2 commits)
      commits = @repository.fetch_commits_by_date_range(
        dir,
        Time.parse("2020-01-15T00:00:00Z"),
        Time.parse("2020-03-15T00:00:00Z")
      )
      
      assert_equal 2, commits.length
      assert_equal "Commit 2", commits[0][:message] # Most recent first
      assert_equal "Commit 1", commits[1][:message]
    end
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
      assert_match(/^[a-f0-9]{40}$/, latest_commit[:sha])
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

  # Tests for deleted repository handling
  test "clone_repository marks repository as not_found when deleted from GitHub" do
    Dir.mktmpdir do |dir|
      # Stub the git clone command to simulate a deleted repository error
      Open3.stubs(:capture3).with(anything) do |cmd|
        if cmd.include?("git clone")
          ["", "fatal: could not read Username for 'https://github.com': No such device or address", double(success?: false)]
        else
          ["", "", double(success?: true)]
        end
      end
      
      # Use the shell command approach that matches the actual implementation
      output = "fatal: could not read Username for 'https://github.com': No such device or address"
      @repository.stubs(:`).returns(output)
      `exit 1` # Set $? to indicate failure
      
      error = assert_raises(Repository::CloneError) do
        @repository.clone_repository(dir)
      end
      
      assert_match(/appears to be deleted or private/, error.message)
      assert_equal 'not_found', @repository.reload.status
    end
  end

  test "clone_repository marks repository as not_found when repository not found" do
    Dir.mktmpdir do |dir|
      # Stub the git clone command to simulate a repository not found error
      output = "ERROR: Repository not found."
      @repository.stubs(:`).returns(output)
      `exit 1` # Set $? to indicate failure
      
      error = assert_raises(Repository::CloneError) do
        @repository.clone_repository(dir)
      end
      
      assert_match(/appears to be deleted or private/, error.message)
      assert_equal 'not_found', @repository.reload.status
    end
  end

  test "clone_repository raises regular CloneError for other failures" do
    Dir.mktmpdir do |dir|
      # Stub the git clone command to simulate a different error
      output = "fatal: unable to access 'https://github.com/test/repo.git/': Connection timed out"
      @repository.stubs(:`).returns(output)
      `exit 1` # Set $? to indicate failure
      
      error = assert_raises(Repository::CloneError) do
        @repository.clone_repository(dir)
      end
      
      assert_match(/Connection timed out/, error.message)
      # Should not change status for other errors
      assert_not_equal 'not_found', @repository.reload.status
    end
  end

  test "sync_commits skips repositories marked as not_found" do
    @repository.update(status: 'not_found')
    
    # Should not attempt to fetch commits
    @repository.expects(:fetch_commits).never
    @repository.expects(:sync_commits_incremental).never
    @repository.expects(:sync_commits_regular).never
    
    result = @repository.sync_commits
    
    assert_nil result
  end

  test "sync_commits processes normally when status is nil" do
    @repository.update(status: nil)
    @repository.stubs(:sync_commits_incremental).returns(10)
    
    result = @repository.sync_commits(incremental: true)
    
    assert_equal 10, result
  end

  test "sync_commits processes normally when status is not 'not_found'" do
    @repository.update(status: 'active')
    @repository.stubs(:sync_commits_incremental).returns(10)
    
    result = @repository.sync_commits(incremental: true)
    
    assert_equal 10, result
  end
end
