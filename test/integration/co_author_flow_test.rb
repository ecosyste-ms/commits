require "test_helper"
require "tmpdir"

class CoAuthorFlowTest < ActiveSupport::TestCase
  def setup
    @host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    @repository = Repository.create!(host: @host, full_name: 'test/repo')
  end

  test "complete flow: from git log to database with co-authors" do
    Dir.mktmpdir do |dir|
      # Initialize a git repo
      `git init #{dir} 2>&1`
      
      # Create commits with various co-author formats
      File.write("#{dir}/file1.txt", "content1")
      `cd #{dir} && git add . && git -c user.name="Main" -c user.email="main@example.com" commit -m "Feature A

Co-authored-by: Alice <alice@example.com>" 2>&1`
      
      File.write("#{dir}/file2.txt", "content2")
      `cd #{dir} && git add . && git -c user.name="Main" -c user.email="main@example.com" commit -m "Feature B  

Co-Authored-By: Bob <bob@example.com>" 2>&1`
      
      File.write("#{dir}/file3.txt", "content3")
      `cd #{dir} && git add . && git -c user.name="Main" -c user.email="main@example.com" commit -m "Feature C

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>" 2>&1`
      
      File.write("#{dir}/file4.txt", "content4")
      `cd #{dir} && git add . && git -c user.name="Solo" -c user.email="solo@example.com" commit -m "Solo commit without co-author" 2>&1`
      
      # Fetch and process commits
      commits = @repository.fetch_commits_internal(dir)
      
      # Verify extraction happened
      assert_equal 4, commits.length
      
      # Check each commit's co-author extraction
      solo_commit = commits.find { |c| c[:message].include?("Solo commit") }
      assert_nil solo_commit[:co_author_email], "Solo commit should not have co-author"
      
      claude_commit = commits.find { |c| c[:message].include?("Feature C") }
      assert_equal "noreply@anthropic.com", claude_commit[:co_author_email], "Claude commit should extract co-author"
      
      bob_commit = commits.find { |c| c[:message].include?("Feature B") }
      assert_equal "bob@example.com", bob_commit[:co_author_email], "Bob commit should extract co-author with brackets"
      
      alice_commit = commits.find { |c| c[:message].include?("Feature A") }
      assert_equal "alice@example.com", alice_commit[:co_author_email], "Alice commit should extract co-author with brackets"
      
      # Save to database using upsert_all (like actual sync)
      Commit.upsert_all(
        commits,
        unique_by: [:repository_id, :sha],
        returning: false
      )
      
      # Verify database persistence
      assert_equal 4, @repository.commits.count
      assert_equal 3, @repository.commits.with_co_author.count
      
      # Verify specific co-authors
      assert_equal 1, @repository.commits.where(co_author_email: 'noreply@anthropic.com').count
      assert_equal 1, @repository.commits.where(co_author_email: 'alice@example.com').count
      assert_equal 1, @repository.commits.where(co_author_email: 'bob@example.com').count
    end
  end

  test "batch processing maintains co-author extraction" do
    Dir.mktmpdir do |dir|
      `git init #{dir} 2>&1`
      
      # Create multiple commits
      10.times do |i|
        File.write("#{dir}/file#{i}.txt", "content#{i}")
        co_author = i.even? ? "\n\nCo-authored-by: Helper#{i} <helper#{i}@example.com>" : ""
        `cd #{dir} && git add . && git -c user.name="Dev" -c user.email="dev@example.com" commit -m "Commit #{i}#{co_author}" 2>&1`
      end
      
      # Test batch processing
      commits = @repository.fetch_commits_batch(dir, 0, 5)
      assert_equal 5, commits.length
      
      # Check that co-authors were extracted in batch
      co_authored = commits.select { |c| c[:co_author_email] }
      assert co_authored.length > 0, "Should have some co-authored commits in batch"
      
      # Test next batch
      commits2 = @repository.fetch_commits_batch(dir, 5, 5)
      assert_equal 5, commits2.length
    end
  end

  test "incremental sync preserves co-author data" do
    Dir.mktmpdir do |dir|
      `git init #{dir} 2>&1`
      
      # Initial commits
      File.write("#{dir}/file1.txt", "v1")
      `cd #{dir} && git add . && git -c user.name="Dev" -c user.email="dev@example.com" commit -m "Initial

Co-authored-by: Assistant <assistant@example.com>" 2>&1`
      
      # First sync
      commits = @repository.fetch_commits_internal(dir)
      Commit.upsert_all(commits, unique_by: [:repository_id, :sha])
      
      initial_count = @repository.commits.count
      initial_co_authored = @repository.commits.with_co_author.count
      
      # Add more commits
      File.write("#{dir}/file2.txt", "v2")
      `cd #{dir} && git add . && git -c user.name="Dev" -c user.email="dev@example.com" commit -m "Update

Co-authored-by: Helper <helper@example.com>" 2>&1`
      
      # Incremental sync - set last_synced_commit to the first (newest) commit
      # so we only get commits after it
      first_sha = commits.first[:sha]
      @repository.update(last_synced_commit: first_sha, total_commits: 1)
      new_commits = @repository.fetch_commits_internal(dir)
      
      # Should only get the new commit added after the first sync
      assert_equal 1, new_commits.length
      assert_equal "helper@example.com", new_commits.first[:co_author_email]
      
      # Save and verify
      Commit.upsert_all(new_commits, unique_by: [:repository_id, :sha])
      assert_equal initial_count + 1, @repository.commits.count
      assert_equal initial_co_authored + 1, @repository.commits.with_co_author.count
    end
  end

  test "parse methods handle edge cases" do
    # Empty/nil cases
    assert_nil Commit.extract_co_author_from_message(nil)
    assert_nil Commit.extract_co_author_from_message("")
    assert_nil Commit.extract_co_author_from_message("Regular commit message")
    
    # Malformed cases (no angle brackets)
    assert_nil Commit.extract_co_author_from_message("Co-authored-by: Just a name")
    assert_nil Commit.extract_co_author_from_message("Co-authored-by: email@example.com")
    
    # Valid edge cases with proper format
    assert_equal "user@domain.co.uk", Commit.extract_co_author_from_message("Co-authored-by: Name <user@domain.co.uk>")
    assert_equal "user+tag@example.com", Commit.extract_co_author_from_message("Co-authored-by: Name <user+tag@example.com>")
    assert_equal "123@users.noreply.github.com", Commit.extract_co_author_from_message("Co-authored-by: User <123@users.noreply.github.com>")
  end

  test "statistics queries work correctly" do
    # Create test data
    messages = [
      "Fix A\n\nCo-authored-by: Claude <noreply@anthropic.com>",
      "Fix B\n\nCo-authored-by: Claude <noreply@anthropic.com>",
      "Fix C\n\nCo-authored-by: Assistant <assistant@ai.com>",
      "Solo commit",
      "Another solo commit"
    ]
    
    messages.each_with_index do |msg, i|
      @repository.commits.create!(
        sha: "sha#{i}",
        message: msg,
        timestamp: Time.now,
        author: "Dev <dev@example.com>",
        committer: "Dev <dev@example.com>",
        stats: [1, 2, 3]
      )
    end
    
    # Test statistics
    assert_equal 5, @repository.commits.count
    assert_equal 3, @repository.commits.with_co_author.count
    assert_equal 2, @repository.commits.where(co_author_email: 'noreply@anthropic.com').count
    assert_equal 1, @repository.commits.where(co_author_email: 'assistant@ai.com').count
    
    # Test grouping
    co_author_stats = @repository.commits
                                 .with_co_author
                                 .group(:co_author_email)
                                 .count
    
    assert_equal 2, co_author_stats['noreply@anthropic.com']
    assert_equal 1, co_author_stats['assistant@ai.com']
  end
end