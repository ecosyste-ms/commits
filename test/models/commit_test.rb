require "test_helper"

class CommitTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
  end

  context 'validations' do
    should validate_presence_of(:sha)
    should validate_uniqueness_of(:sha).scoped_to(:repository_id)
  end

  test 'co_authors returns empty array when message is nil' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    commit = Commit.new(repository: repository, sha: 'abc123', message: nil)
    assert_equal [], commit.co_authors
  end

  test 'co_authors returns empty array when message is blank' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    commit = Commit.new(repository: repository, sha: 'abc123', message: '')
    assert_equal [], commit.co_authors
  end

  test 'co_authors returns empty array when no co-authors in message' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    commit = Commit.new(repository: repository, sha: 'abc123', message: 'Regular commit message')
    assert_equal [], commit.co_authors
  end

  test 'co_authors extracts single co-author' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix bug\n\nCo-authored-by: Jane Doe <jane@example.com>"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    expected = [{name: 'Jane Doe', email: 'jane@example.com'}]
    assert_equal expected, commit.co_authors
  end

  test 'co_authors extracts multiple co-authors' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Pair programming session\n\nCo-authored-by: Jane Doe <jane@example.com>\nCo-authored-by: John Smith <john@example.com>"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    expected = [
      {name: 'Jane Doe', email: 'jane@example.com'},
      {name: 'John Smith', email: 'john@example.com'}
    ]
    assert_equal expected, commit.co_authors
  end

  test 'co_authors handles case-insensitive Co-authored-by' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix\n\nco-authored-by: Jane Doe <jane@example.com>\nCO-AUTHORED-BY: John Smith <john@example.com>"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    assert_equal 2, commit.co_authors.length
  end

  test 'co_authors strips whitespace from names and emails' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix\n\nCo-authored-by:  Jane Doe   < jane@example.com >"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    expected = [{name: 'Jane Doe', email: 'jane@example.com'}]
    assert_equal expected, commit.co_authors
  end

  test 'co_authors handles names with special characters' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix\n\nCo-authored-by: José García-López <jose@example.com>"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    expected = [{name: 'José García-López', email: 'jose@example.com'}]
    assert_equal expected, commit.co_authors
  end

  test 'signed_off_by returns empty array when message is nil' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    commit = Commit.new(repository: repository, sha: 'abc123', message: nil)
    assert_equal [], commit.signed_off_by
  end

  test 'signed_off_by returns empty array when no sign-offs in message' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    commit = Commit.new(repository: repository, sha: 'abc123', message: 'Regular commit message')
    assert_equal [], commit.signed_off_by
  end

  test 'signed_off_by extracts single sign-off' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix bug\n\nSigned-off-by: Jane Doe <jane@example.com>"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    expected = [{name: 'Jane Doe', email: 'jane@example.com'}]
    assert_equal expected, commit.signed_off_by
  end

  test 'signed_off_by extracts multiple sign-offs' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Kernel patch\n\nSigned-off-by: Jane Doe <jane@example.com>\nSigned-off-by: John Smith <john@example.com>"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    expected = [
      {name: 'Jane Doe', email: 'jane@example.com'},
      {name: 'John Smith', email: 'john@example.com'}
    ]
    assert_equal expected, commit.signed_off_by
  end

  test 'signed_off_by handles case-insensitive Signed-off-by' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix\n\nsigned-off-by: Jane Doe <jane@example.com>\nSIGNED-OFF-BY: John Smith <john@example.com>"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    assert_equal 2, commit.signed_off_by.length
  end

  test 'commit can have both co-authors and sign-offs' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix\n\nCo-authored-by: Jane Doe <jane@example.com>\nSigned-off-by: John Smith <john@example.com>"
    commit = Commit.new(repository: repository, sha: 'abc123', message: message)
    
    assert_equal [{name: 'Jane Doe', email: 'jane@example.com'}], commit.co_authors
    assert_equal [{name: 'John Smith', email: 'john@example.com'}], commit.signed_off_by
  end

  test 'extract_co_author_email sets co_author_email on save' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix bug\n\nCo-authored-by: Claude <noreply@anthropic.com>"
    commit = Commit.create!(
      repository: repository, 
      sha: 'test123', 
      message: message,
      timestamp: Time.now,
      author: 'Test Author <test@example.com>',
      committer: 'Test Committer <test@example.com>',
      stats: [1, 2, 3]
    )
    
    assert_equal 'noreply@anthropic.com', commit.co_author_email
  end

  test 'extract_co_author_email handles multiple co-authors by taking first' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix\n\nCo-authored-by: First <first@example.com>\nCo-authored-by: Second <second@example.com>"
    commit = Commit.create!(
      repository: repository, 
      sha: 'test456', 
      message: message,
      timestamp: Time.now,
      author: 'Test Author <test@example.com>',
      committer: 'Test Committer <test@example.com>',
      stats: [1, 2, 3]
    )
    
    assert_equal 'first@example.com', commit.co_author_email
  end

  test 'extract_co_author_email downcases email' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    message = "Fix\n\nCo-authored-by: User <User@Example.COM>"
    commit = Commit.create!(
      repository: repository, 
      sha: 'test789', 
      message: message,
      timestamp: Time.now,
      author: 'Test Author <test@example.com>',
      committer: 'Test Committer <test@example.com>',
      stats: [1, 2, 3]
    )
    
    assert_equal 'user@example.com', commit.co_author_email
  end

  test 'extract_co_author_email is nil when no co-author' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    commit = Commit.create!(
      repository: repository, 
      sha: 'test000', 
      message: 'Regular commit message',
      timestamp: Time.now,
      author: 'Test Author <test@example.com>',
      committer: 'Test Committer <test@example.com>',
      stats: [1, 2, 3]
    )
    
    assert_nil commit.co_author_email
  end

  test 'extract_co_author_from_message class method returns nil for blank message' do
    assert_nil Commit.extract_co_author_from_message(nil)
    assert_nil Commit.extract_co_author_from_message('')
    assert_nil Commit.extract_co_author_from_message('   ')
  end

  test 'extract_co_author_from_message class method extracts email' do
    message = "Fix\n\nCo-authored-by: Claude <noreply@anthropic.com>"
    assert_equal 'noreply@anthropic.com', Commit.extract_co_author_from_message(message)
  end

  test 'extract_co_author_from_message class method is case-insensitive' do
    message = "Fix\n\nco-authored-by: User <test@example.com>"
    assert_equal 'test@example.com', Commit.extract_co_author_from_message(message)
    
    message2 = "Fix\n\nCO-AUTHORED-BY: User <test@example.com>"
    assert_equal 'test@example.com', Commit.extract_co_author_from_message(message2)
  end

  test 'extract_co_author_from_message handles standard format' do
    # With angle brackets (standard format)
    message = "Fix\n\nCo-authored-by: Claude <noreply@anthropic.com>"
    assert_equal 'noreply@anthropic.com', Commit.extract_co_author_from_message(message)
  end
  
  test 'extract_co_author_from_message returns nil for non-standard formats' do
    # Without angle brackets - should return nil
    message1 = "Fix\n\nCo-Authored-By: Claude noreply@anthropic.com"
    assert_nil Commit.extract_co_author_from_message(message1)
    
    # Just email without angle brackets - should return nil
    message2 = "Fix\n\nCo-authored-by: noreply@anthropic.com"
    assert_nil Commit.extract_co_author_from_message(message2)
  end

  test 'extract_co_author_from_message handles real Claude Code format' do
    # Actual format from Claude Code commits
    message = "feat: update issue-notify to use repository_dispatch\n\n🤖 Generated with [Claude Code](https://claude.ai/code)\n\nCo-Authored-By: Claude <noreply@anthropic.com>"
    assert_equal 'noreply@anthropic.com', Commit.extract_co_author_from_message(message)
  end

  test 'extract_co_author_from_message handles GitHub format variations' do
    # GitHub desktop format
    message1 = "Update README\n\nCo-authored-by: John Doe <john@users.noreply.github.com>"
    assert_equal 'john@users.noreply.github.com', Commit.extract_co_author_from_message(message1)
    
    # Multiple co-authors (should get first)
    message2 = "Pair programming\n\nCo-authored-by: Alice <alice@example.com>\nCo-authored-by: Bob <bob@example.com>"
    assert_equal 'alice@example.com', Commit.extract_co_author_from_message(message2)
  end

  test 'co_authors method works alongside co_author_email field' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    
    message = "Fix\n\nCo-authored-by: Alice <alice@example.com>\nCo-authored-by: Bob <bob@example.com>"
    commit = Commit.create!(
      repository: repository,
      sha: 'test_both',
      message: message,
      timestamp: Time.now,
      author: 'Main <main@example.com>',
      committer: 'Main <main@example.com>',
      stats: [1, 2, 3]
    )
    
    # co_author_email should have first co-author
    assert_equal 'alice@example.com', commit.co_author_email
    
    # co_authors should return all co-authors
    assert_equal 2, commit.co_authors.length
    assert_equal 'Alice', commit.co_authors[0][:name]
    assert_equal 'alice@example.com', commit.co_authors[0][:email]
    assert_equal 'Bob', commit.co_authors[1][:name]
    assert_equal 'bob@example.com', commit.co_authors[1][:email]
  end

  test 'with_co_author scope returns commits with co_author_email' do
    host = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'github')
    repository = Repository.create!(full_name: 'test/repo', host: host)
    
    # Create commit with co-author
    commit_with = Commit.create!(
      repository: repository,
      sha: 'with123',
      message: "Fix\n\nCo-authored-by: Claude <noreply@anthropic.com>",
      timestamp: Time.now,
      author: 'Test <test@example.com>',
      committer: 'Test <test@example.com>',
      stats: [1, 2, 3]
    )
    
    # Create commit without co-author
    commit_without = Commit.create!(
      repository: repository,
      sha: 'without123',
      message: 'Regular commit',
      timestamp: Time.now,
      author: 'Test <test@example.com>',
      committer: 'Test <test@example.com>',
      stats: [1, 2, 3]
    )
    
    co_authored = Commit.with_co_author
    assert_includes co_authored, commit_with
    assert_not_includes co_authored, commit_without
  end
end
