require "test_helper"
require "rake"

class TakedownRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("takedown:hide_user")
    @host = create(:host, :github)
  end

  teardown do
    ENV.delete('LOGIN')
    ENV.delete('HOST')
    ENV.delete('EMAIL')
  end

  test "hide_user marks owner and committer hidden and destroys repositories" do
    owner = create(:owner, host: @host, login: 'someuser')
    committer = create(:committer, host: @host, login: 'someuser')
    repo = create(:repository, host: @host, full_name: 'someuser/thing', owner: 'someuser')
    other = create(:repository, host: @host, full_name: 'other/thing', owner: 'other')

    ENV['LOGIN'] = 'someuser'
    capture_io { Rake::Task["takedown:hide_user"].execute }

    assert owner.reload.hidden?
    assert committer.reload.hidden?
    assert_nil Repository.find_by(id: repo.id)
    refute_nil Repository.find_by(id: other.id)
  end

  test "hide_user creates a hidden owner when none exists" do
    ENV['LOGIN'] = 'newuser'
    capture_io { Rake::Task["takedown:hide_user"].execute }

    owner = @host.owners.find_by('lower(login) = ?', 'newuser')
    refute_nil owner
    assert owner.hidden?
  end

  test "hide_user aborts without LOGIN" do
    assert_raises(SystemExit) do
      capture_io { Rake::Task["takedown:hide_user"].execute }
    end
  end

  test "hide_committer creates hidden committer and scrubs existing data" do
    repo = create(:repository, host: @host, full_name: 'org/thing', committers: [
      { 'name' => 'Keep', 'email' => 'keep@example.com', 'count' => 5 },
      { 'name' => 'Hide', 'email' => 'hide@example.com', 'count' => 1 }
    ], past_year_committers: [
      { 'name' => 'Hide', 'email' => 'hide@example.com', 'count' => 1 }
    ])
    other = create(:repository, host: @host, full_name: 'org/other', committers: [
      { 'name' => 'Keep', 'email' => 'keep@example.com', 'count' => 5 }
    ])
    create(:commit, repository: repo, sha: 'aaa', author: 'Hide <hide@example.com>', committer: 'Hide <hide@example.com>')
    create(:commit, repository: repo, sha: 'bbb', author: 'Keep <keep@example.com>', committer: 'Keep <keep@example.com>')

    ENV['EMAIL'] = 'hide@example.com'
    out, _ = capture_io { Rake::Task["takedown:hide_committer"].execute }
    assert_match "scrubbed 1 repositories", out

    committer = @host.committers.email('hide@example.com').first
    refute_nil committer
    assert committer.hidden?
    assert Contribution.exists?(repository_id: repo.id, committer_id: committer.id)

    repo.reload
    assert_equal ['keep@example.com'], repo.committers.map { |c| c['email'] }
    assert_equal [], repo.past_year_committers
    assert_equal 'redacted <redacted>', repo.commits.find_by(sha: 'aaa').author
    assert_equal 'Keep <keep@example.com>', repo.commits.find_by(sha: 'bbb').author

    refute Contribution.exists?(repository_id: other.id, committer_id: committer.id)
  end

  test "hide_committer marks existing committer hidden" do
    existing = create(:committer, host: @host, login: nil, emails: ['hide@example.com'], hidden: false)

    ENV['EMAIL'] = 'hide@example.com'
    capture_io { Rake::Task["takedown:hide_committer"].execute }

    assert existing.reload.hidden?
  end

  test "hide_committer aborts without EMAIL" do
    assert_raises(SystemExit) do
      capture_io { Rake::Task["takedown:hide_committer"].execute }
    end
  end
end
