require 'test_helper'

class ApiV1HostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github', last_synced_at: Time.now, repositories_count: 1, commits_count: 1)
  end

  test 'lists hosts' do
    get api_v1_hosts_path
    assert_response :success
    assert_template 'hosts/index', file: 'hosts/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get a host' do
    get api_v1_host_path(id: @host.name)
    assert_response :success
    assert_template 'hosts/show', file: 'hosts/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["name"], 'GitHub'
  end

  test 'redirect uppercase host names to lowercase' do
    get api_v1_host_path(id: @host.name.upcase)
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_path(@host.name)
  end

  test 'redirect mixed case host names to lowercase' do
    mixed_case_name = @host.name.split('.').map(&:capitalize).join('.')
    get api_v1_host_path(id: mixed_case_name)
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_path(@host.name)
  end

  test 'not redirect exact case matches' do
    get api_v1_host_path(id: @host.name)
    assert_response :success
    assert_template 'hosts/show', file: 'hosts/show.json.jbuilder'
  end

  test 'return 404 for non-existent hosts with any case' do
    get api_v1_host_path(id: "NonExistentHost.com")
    assert_response :not_found
  end
end