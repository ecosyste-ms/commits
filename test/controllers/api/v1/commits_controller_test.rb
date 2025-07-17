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