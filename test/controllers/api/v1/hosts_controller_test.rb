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
end