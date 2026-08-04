require 'test_helper'

class CommitterDedupeTest < ActiveSupport::TestCase
  setup do
    @host = create(:host)
  end

  test 'merge! combines emails, repoints contributions and removes duplicates' do
    keeper = create(:committer, host: @host, login: 'alice', emails: ['a@one.com'])
    dupe1  = create(:committer, host: @host, login: 'alice', emails: ['a@two.com'])
    dupe2  = create(:committer, host: @host, login: 'alice', emails: ['a@one.com', 'a@three.com'], hidden: true)

    repo1 = create(:repository, host: @host)
    repo2 = create(:repository, host: @host)

    create(:contribution, committer: keeper, repository: repo1, commit_count: 5)
    create(:contribution, committer: dupe1,  repository: repo1, commit_count: 3)
    create(:contribution, committer: dupe2,  repository: repo2, commit_count: 7)

    keeper.merge!([dupe1, dupe2])

    keeper.reload
    assert_equal %w[a@one.com a@two.com a@three.com].sort, keeper.emails.sort
    assert keeper.hidden?
    assert_equal 2, keeper.contributions.count
    assert_equal 8, keeper.contributions.find_by(repository_id: repo1.id).commit_count
    assert_equal 7, keeper.contributions.find_by(repository_id: repo2.id).commit_count
    assert_nil Committer.find_by(id: dupe1.id)
    assert_nil Committer.find_by(id: dupe2.id)
  end

  test 'dedupe finds and merges all duplicate groups by host_id and login' do
    3.times { create(:committer, host: @host, login: 'bob', emails: ["bob#{_1}@x.com"]) }
    other_host = create(:host)
    create(:committer, host: other_host, login: 'bob', emails: ['bob@other.com'])
    create(:committer, host: @host, login: 'carol')

    removed = Committer.dedupe

    assert_equal 2, removed
    assert_equal 1, Committer.where(host: @host, login: 'bob').count
    assert_equal 1, Committer.where(host: other_host, login: 'bob').count
    assert_equal %w[bob0@x.com bob1@x.com bob2@x.com].sort, Committer.find_by(host: @host, login: 'bob').emails.sort
  end

  test 'dedupe ignores rows with blank login' do
    create(:committer, :no_login, host: @host)
    create(:committer, :no_login, host: @host)

    assert_equal 0, Committer.dedupe
    assert_equal 2, Committer.where(host: @host, login: nil).count
  end

  test 'backfill_emails_from_repositories merges emails from repository JSON into committers' do
    existing = create(:committer, host: @host, login: 'johndoe', emails: ['old@example.com'])
    create(:repository, :with_commits, host: @host)
    create(:repository, host: @host, committers: [
      { 'login' => 'johndoe', 'email' => 'john@example.com', 'count' => 1 },
      { 'login' => 'newperson', 'email' => 'new@example.com', 'count' => 2 },
      { 'login' => '', 'email' => 'anon@example.com', 'count' => 1 },
      { 'login' => 'noemail', 'email' => '', 'count' => 1 }
    ])

    updated = Committer.backfill_emails_from_repositories(batch_size: 10)

    existing.reload
    assert_includes existing.emails, 'old@example.com'
    assert_includes existing.emails, 'john@example.com'

    created = Committer.find_by(host: @host, login: 'newperson')
    assert created
    assert_equal ['new@example.com'], created.emails

    assert Committer.find_by(host: @host, login: 'janesmith')
    assert_nil Committer.find_by(host: @host, login: '')
    assert_nil Committer.find_by(host: @host, login: 'noemail')
    assert_operator updated, :>=, 3
  end

  test 'backfill_emails_from_repositories skips when emails already present' do
    create(:committer, host: @host, login: 'johndoe', emails: ['john@example.com'])
    create(:repository, host: @host, committers: [{ 'login' => 'johndoe', 'email' => 'john@example.com', 'count' => 1 }])

    assert_equal 0, Committer.backfill_emails_from_repositories(batch_size: 10)
  end
end
