require 'test_helper'

class ApiV1RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos', last_synced_at: Time.now, total_commits: 100, total_committers: 10)
  end

  test 'list repositories for a host' do
    get api_v1_host_repositories_path(host_id: @host.name)
    assert_response :success
    assert_template 'repositories/index', file: 'repositories/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'redirect uppercase host names to lowercase for repositories list' do
    get api_v1_host_repositories_path(host_id: @host.name.upcase)
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_repositories_path(@host.name)
  end

  test 'redirect mixed case host names to lowercase for repositories list' do
    mixed_case_name = @host.name.split('.').map(&:capitalize).join('.')
    get api_v1_host_repositories_path(host_id: mixed_case_name)
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_repositories_path(@host.name)
  end

  test 'get a repository for a host' do
    get api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["full_name"], @repository.full_name
  end

  test 'redirect uppercase host names to lowercase for repository show' do
    get api_v1_host_repository_path(host_id: @host.name.upcase, id: @repository.full_name)
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_repository_path(@host.name, @repository.full_name)
  end

  test 'redirect mixed case host names to lowercase for repository show' do
    mixed_case_name = @host.name.split('.').map(&:capitalize).join('.')
    get api_v1_host_repository_path(host_id: mixed_case_name, id: @repository.full_name)
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_repository_path(@host.name, @repository.full_name)
  end

  test 'lookup a repository for a host' do
    get api_v1_repositories_lookup_path(url: 'https://github.com/ecosyste-ms/repos/')
    assert_response :redirect
  end

  test 'lookup a repository using git@ SSH format' do
    get api_v1_repositories_lookup_path(url: 'git@github.com:ecosyste-ms/repos.git')
    assert_response :redirect
  end
end