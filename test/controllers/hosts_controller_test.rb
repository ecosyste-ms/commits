require 'test_helper'

class HostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, :github)
    @invisible_host = create(:host, :invisible)
    @host_with_repos = create(:host, :with_repositories, name: "TestHost", repositories_count: 5, commits_count: 100)
  end

  context "GET #index" do
    should "return success" do
      get hosts_path
      assert_response :success
      assert_template 'hosts/index'
    end

    should "only show visible hosts" do
      get hosts_path
      assert_response :success
      assert_select "a[href=?]", host_path(@host.name)
      assert_select "a[href=?]", host_path(@invisible_host.name), false
    end

    should "order hosts by repositories_count and commits_count" do
      high_repo_host = create(:host, name: "HighRepo", repositories_count: 1000, commits_count: 5000)
      low_repo_host = create(:host, name: "LowRepo", repositories_count: 1, commits_count: 10)
      
      get hosts_path
      assert_response :success
      
      body = response.body
      assert body.index(high_repo_host.name) < body.index(low_repo_host.name)
    end

    should "limit to 20 hosts" do
      create_list(:host, 25, repositories_count: 10, commits_count: 100)
      
      get hosts_path
      assert_response :success
      assert_select ".host", maximum: 20
    end

    should "show recent repositories" do
      recent_repo = create(:repository, :with_commits, host: @host, last_synced_at: 1.hour.ago)
      old_repo = create(:repository, :with_commits, host: @host, last_synced_at: 1.month.ago)
      
      get hosts_path
      assert_response :success
    end

    should "handle empty hosts list" do
      Host.destroy_all
      
      get hosts_path
      assert_response :success
      assert_template 'hosts/index'
    end
  end

  context "GET #show" do
    should "return success for existing host" do
      get host_path(@host.name)
      assert_response :success
      assert_template 'hosts/show'
    end

    should "return 404 for non-existent host" do
      get host_path("NonExistentHost")
      assert_response :not_found
    end

    should "show host repositories" do
      repo1 = create(:repository, :with_commits, host: @host, full_name: "owner/repo1")
      repo2 = create(:repository, :with_commits, host: @host, full_name: "owner/repo2")
      
      get host_path(@host.name)
      assert_response :success
      assert_match repo1.full_name, response.body
      assert_match repo2.full_name, response.body
    end

    should "only show visible repositories" do
      visible_repo = create(:repository, :with_commits, host: @host, full_name: "owner/visible")
      invisible_repo = create(:repository, :not_synced, host: @host, full_name: "owner/invisible")
      
      get host_path(@host.name)
      assert_response :success
      assert_match visible_repo.full_name, response.body
      assert_no_match invisible_repo.full_name, response.body
    end

    should "support sorting repositories" do
      repo_a = create(:repository, :with_commits, host: @host, full_name: "owner/aaa", stargazers_count: 100)
      repo_z = create(:repository, :with_commits, host: @host, full_name: "owner/zzz", stargazers_count: 200)
      
      get host_path(@host.name), params: { sort: "full_name", order: "asc" }
      assert_response :success
      body = response.body
      assert body.index(repo_a.full_name) < body.index(repo_z.full_name)
      
      get host_path(@host.name), params: { sort: "full_name", order: "desc" }
      assert_response :success
      body = response.body
      assert body.index(repo_z.full_name) < body.index(repo_a.full_name)
    end

    should "support multiple sort options" do
      get host_path(@host.name), params: { sort: "full_name,stargazers_count", order: "asc,desc" }
      assert_response :success
    end

    should "default to last_synced_at DESC when no sort specified" do
      old_repo = create(:repository, :with_commits, host: @host, full_name: "owner/old", last_synced_at: 1.week.ago)
      new_repo = create(:repository, :with_commits, host: @host, full_name: "owner/new", last_synced_at: 1.hour.ago)
      
      get host_path(@host.name)
      assert_response :success
      body = response.body
      assert body.index(new_repo.full_name) < body.index(old_repo.full_name)
    end

    should "support pagination" do
      create_list(:repository, 150, :with_commits, host: @host)
      
      get host_path(@host.name)
      assert_response :success
      
      get host_path(@host.name), params: { page: 2 }
      assert_response :success
    end

    should "set proper cache headers" do
      get host_path(@host.name)
      assert_response :success
      assert response.headers["Cache-Control"].present?
    end

    should "include host statistics" do
      get host_path(@host.name)
      assert_response :success
      assert_match @host.repositories_count.to_s, response.body
      # Note: commits_count is not displayed on the show page, only repositories_count
    end

    should "handle hosts with special characters in name" do
      special_host = create(:host, name: "host.with-special_chars")
      get host_path(special_host.name)
      assert_response :success
    end
  end
end