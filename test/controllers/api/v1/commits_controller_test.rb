require 'test_helper'

class ApiV1CommitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos', last_synced_at: Time.now, total_commits: 100, total_committers: 10)
    @commit = @repository.commits.create(sha: '1234567890', timestamp: Time.now, author: 'author', message: 'message')
  end

  test 'list commits for a repository' do
    get api_v1_host_repository_commits_path(host_id: @host.name, repository_id: @repository.full_name)
    assert_response :success
    assert_template 'commits/index', file: 'commits/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'return accepted and start syncing for an unknown repository' do
    SyncRepositoryWorker.expects(:perform_async).with(kind_of(Integer)).returns('job-id')

    get api_v1_host_repository_commits_path(host_id: @host.name, repository_id: 'owner/new-repo')

    assert_response :accepted
    repository = @host.repositories.find_by!(full_name: 'owner/new-repo')
    response_json = JSON.parse(response.body)
    assert_equal 'pending', response_json['status']
    assert_equal api_v1_host_repository_url(@host, repository), response_json['repository_url']
    assert_equal api_v1_host_repository_commits_url(@host, repository), response_json['commits_url']
    assert_equal '60', response.headers['Retry-After']
    assert_includes response.headers['Cache-Control'], 'no-store'
  end

  test 'return accepted for an existing repository that has not synced' do
    repository = @host.repositories.create!(full_name: 'owner/pending-repo')
    SyncRepositoryWorker.expects(:perform_async).with(repository.id).returns('job-id')

    get api_v1_host_repository_commits_path(host_id: @host.name, repository_id: repository.full_name)

    assert_response :accepted
    assert_equal 'pending', JSON.parse(response.body)['status']
  end

  test 'return success for a synced repository with no commits' do
    repository = @host.repositories.create!(
      full_name: 'owner/empty-repo',
      last_synced_at: Time.current,
      total_commits: 0,
      total_committers: 0
    )

    get api_v1_host_repository_commits_path(host_id: @host.name, repository_id: repository.full_name)

    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  test 'do not create a repository for a hidden owner' do
    Owner.create!(host: @host, login: 'hidden-owner', hidden: true)
    SyncRepositoryWorker.expects(:perform_async).never

    assert_no_difference -> { @host.repositories.count } do
      get api_v1_host_repository_commits_path(
        host_id: @host.name,
        repository_id: 'hidden-owner/private-repo'
      )
    end

    assert_response :not_found
  end

  test 'redirect uppercase host names to lowercase' do
    get api_v1_host_repository_commits_path(host_id: @host.name.upcase, repository_id: @repository.full_name)
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_repository_commits_path(@host.name, @repository.full_name)
  end

  test 'redirect mixed case host names to lowercase' do
    mixed_case_name = @host.name.split('.').map(&:capitalize).join('.')
    get api_v1_host_repository_commits_path(host_id: mixed_case_name, repository_id: @repository.full_name)
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_repository_commits_path(@host.name, @repository.full_name)
  end
end
