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
end
