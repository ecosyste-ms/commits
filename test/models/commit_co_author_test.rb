require "test_helper"

class CommitCoAuthorTest < ActiveSupport::TestCase
  def setup
    @host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    @repository = Repository.create!(full_name: 'test/repo', host: @host)
  end

  test "extracts co-author email with standard angle bracket format" do
    examples = [
      ["Fix bug\n\nCo-authored-by: Claude <noreply@anthropic.com>", "noreply@anthropic.com"],
      ["Update\n\nCo-Authored-By: Assistant <assistant@ai.com>", "assistant@ai.com"],
      ["Feature\n\nco-authored-by: User <user@example.com>", "user@example.com"],
      ["Commit\n\nCo-authored-by: John Doe <john@users.noreply.github.com>", "john@users.noreply.github.com"],
      ["Fix\n\nCo-authored-by: User Name <user+tag@example.com>", "user+tag@example.com"],
    ]
    
    examples.each do |message, expected_email|
      assert_equal expected_email, Commit.extract_co_author_from_message(message), 
                   "Failed to extract from: #{message.lines.first}"
    end
  end

  test "returns nil for non-standard formats" do
    examples = [
      "Solo commit",
      "Bad format\n\nCo-authored-by: noreply@anthropic.com",
      "Missing brackets\n\nCo-authored-by: User user@example.com",
      "Just name\n\nCo-authored-by: John Doe",
      "Empty co-author\n\nCo-authored-by:",
      "",
      nil
    ]
    
    examples.each do |message|
      assert_nil Commit.extract_co_author_from_message(message),
                 "Should return nil for: #{message.inspect}"
    end
  end

  test "co_authors method returns array of all co-authors" do
    message = "Pair programming\n\nCo-authored-by: Alice <alice@example.com>\nCo-authored-by: Bob <bob@example.com>"
    commit = Commit.new(repository: @repository, sha: 'test', message: message)
    
    co_authors = commit.co_authors
    assert_equal 2, co_authors.length
    assert_equal "Alice", co_authors[0][:name]
    assert_equal "alice@example.com", co_authors[0][:email]
    assert_equal "Bob", co_authors[1][:name]
    assert_equal "bob@example.com", co_authors[1][:email]
  end

  test "extract_co_author_email uses first co-author" do
    message = "Multiple co-authors\n\nCo-authored-by: First <first@example.com>\nCo-authored-by: Second <second@example.com>"
    commit = Commit.create!(
      repository: @repository,
      sha: 'multi_test',
      message: message,
      timestamp: Time.now,
      author: 'Author <author@example.com>',
      committer: 'Committer <committer@example.com>',
      stats: [1, 2, 3]
    )
    
    assert_equal "first@example.com", commit.co_author_email
  end

  test "co_author_email is downcased" do
    message = "Fix\n\nCo-authored-by: User <User@Example.COM>"
    commit = Commit.create!(
      repository: @repository,
      sha: 'case_test',
      message: message,
      timestamp: Time.now,
      author: 'Author <author@example.com>',
      committer: 'Committer <committer@example.com>',
      stats: [1, 2, 3]
    )
    
    assert_equal "user@example.com", commit.co_author_email
  end

  test "handles real Claude Code commit format" do
    message = "feat: update issue-notify to use repository_dispatch

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
    
    assert_equal "noreply@anthropic.com", Commit.extract_co_author_from_message(message)
  end

  test "handles GitHub co-author format variations" do
    examples = [
      ["Merge pull request #123\n\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>", 
       "49699333+dependabot[bot]@users.noreply.github.com"],
      ["Update deps\n\nCo-authored-by: github-actions[bot] <github-actions[bot]@users.noreply.github.com>",
       "github-actions[bot]@users.noreply.github.com"],
      ["Pair work\n\nCo-authored-by: John Doe <1234567+johndoe@users.noreply.github.com>",
       "1234567+johndoe@users.noreply.github.com"]
    ]
    
    examples.each do |message, expected|
      assert_equal expected, Commit.extract_co_author_from_message(message)
    end
  end

  test "with_co_author scope filters correctly" do
    # Create commits with and without co-authors
    Commit.create!(
      repository: @repository,
      sha: 'with_co_1',
      message: "Fix\n\nCo-authored-by: Helper <helper@example.com>",
      timestamp: Time.now,
      author: 'Dev <dev@example.com>',
      committer: 'Dev <dev@example.com>',
      stats: [1, 2, 3]
    )
    
    Commit.create!(
      repository: @repository,
      sha: 'without_1',
      message: "Solo work",
      timestamp: Time.now,
      author: 'Dev <dev@example.com>',
      committer: 'Dev <dev@example.com>',
      stats: [1, 2, 3]
    )
    
    Commit.create!(
      repository: @repository,
      sha: 'with_co_2',
      message: "Feature\n\nCo-authored-by: Assistant <assistant@ai.com>",
      timestamp: Time.now,
      author: 'Dev <dev@example.com>',
      committer: 'Dev <dev@example.com>',
      stats: [1, 2, 3]
    )
    
    # Test scope
    all_commits = @repository.commits
    co_authored = @repository.commits.with_co_author
    
    assert_equal 3, all_commits.count
    assert_equal 2, co_authored.count
    assert co_authored.all? { |c| c.co_author_email.present? }
  end

  test "bulk upsert preserves co_author_email" do
    commits_data = [
      {
        repository_id: @repository.id,
        sha: 'bulk1',
        message: "Fix\n\nCo-authored-by: Claude <noreply@anthropic.com>",
        timestamp: Time.now,
        author: 'Dev <dev@example.com>',
        committer: 'Dev <dev@example.com>',
        stats: [1, 2, 3],
        co_author_email: Commit.extract_co_author_from_message("Fix\n\nCo-authored-by: Claude <noreply@anthropic.com>")
      },
      {
        repository_id: @repository.id,
        sha: 'bulk2',
        message: "Solo commit",
        timestamp: Time.now,
        author: 'Dev <dev@example.com>',
        committer: 'Dev <dev@example.com>',
        stats: [1, 2, 3],
        co_author_email: Commit.extract_co_author_from_message("Solo commit")
      }
    ]
    
    Commit.upsert_all(commits_data, unique_by: [:repository_id, :sha])
    
    bulk1 = Commit.find_by(sha: 'bulk1')
    bulk2 = Commit.find_by(sha: 'bulk2')
    
    assert_equal 'noreply@anthropic.com', bulk1.co_author_email
    assert_nil bulk2.co_author_email
  end
end