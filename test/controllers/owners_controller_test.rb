require 'test_helper'

class OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, :github)
    @owner1_repos = 3.times.map { |i| create(:repository, :with_commits, host: @host, owner: "owner1", full_name: "owner1/repo#{i}") }
    @owner2_repos = 5.times.map { |i| create(:repository, :with_commits, host: @host, owner: "owner2", full_name: "owner2/repo#{i}") }
    @owner3_repos = [create(:repository, :with_commits, host: @host, owner: "owner3", full_name: "owner3/repo")]
  end

  context "GET #index" do
    should "return success" do
      get host_owners_path(@host.name)
      assert_response :success
      assert_template 'owners/index'
    end

    should "redirect uppercase host names to lowercase" do
      get host_owners_path(@host.name.upcase)
      assert_response :moved_permanently
      assert_redirected_to host_owners_path(@host.name)
    end

    should "redirect mixed case host names to lowercase" do
      mixed_case_name = @host.name.split('.').map(&:capitalize).join('.')
      get host_owners_path(mixed_case_name)
      assert_response :moved_permanently
      assert_redirected_to host_owners_path(@host.name)
    end

    should "display all owners with repository counts" do
      get host_owners_path(@host.name)
      assert_response :success
      
      assert_match "owner1", response.body
      assert_match "owner2", response.body
      assert_match "owner3", response.body
      
      # Check repository counts are displayed
      assert_match "3", response.body  # owner1's repo count
      assert_match "5", response.body  # owner2's repo count
      assert_match "1", response.body  # owner3's repo count
    end

    should "order owners by repository count descending, then by name" do
      get host_owners_path(@host.name)
      assert_response :success
      
      body = response.body
      # owner2 (5 repos) should come before owner1 (3 repos)
      assert body.index("owner2") < body.index("owner1")
      # owner1 (3 repos) should come before owner3 (1 repo)
      assert body.index("owner1") < body.index("owner3")
    end

    should "handle host with no repositories" do
      empty_host = create(:host, name: "EmptyHost")
      
      get host_owners_path(empty_host.name)
      assert_response :success
      assert_template 'owners/index'
    end

    should "return 404 for non-existent host" do
      get host_owners_path("NonExistentHost")
      assert_response :not_found
    end

    should "only count visible repositories" do
      # Create an inactive repository
      create(:repository, host: @host, owner: "owner4", full_name: "owner4/repo", status: "not_found")
      
      get host_owners_path(@host.name)
      assert_response :success
      
      # owner4 should not appear since their only repo is not active
      assert_no_match "owner4", response.body
    end

    should "handle owners with special characters" do
      create(:repository, :with_commits, host: @host, owner: "special-owner_123", full_name: "special-owner_123/repo")
      
      get host_owners_path(@host.name)
      assert_response :success
      assert_match "special-owner_123", response.body
    end

    should "set proper cache headers" do
      get host_owners_path(@host.name)
      assert_response :success
      assert response.headers["Cache-Control"].present?
      assert_match "public", response.headers["Cache-Control"]
      assert_match "s-maxage=21600", response.headers["Cache-Control"]
    end
  end

  context "GET #show" do
    should "return success for existing owner" do
      get host_owner_path(@host.name, "owner1")
      assert_response :success
      assert_template 'owners/show'
    end

    should "redirect uppercase host names to lowercase" do
      get host_owner_path(@host.name.upcase, "owner1")
      assert_response :moved_permanently
      assert_redirected_to host_owner_path(@host.name, "owner1")
    end

    should "redirect mixed case host names to lowercase" do
      mixed_case_name = @host.name.split('.').map(&:capitalize).join('.')
      get host_owner_path(mixed_case_name, "owner1")
      assert_response :moved_permanently
      assert_redirected_to host_owner_path(@host.name, "owner1")
    end

    should "display owner's repositories" do
      get host_owner_path(@host.name, "owner1")
      assert_response :success
      
      @owner1_repos.each do |repo|
        assert_match repo.full_name, response.body
      end
    end

    should "not display other owners' repositories" do
      get host_owner_path(@host.name, "owner1")
      assert_response :success
      
      @owner2_repos.each do |repo|
        assert_no_match repo.full_name, response.body
      end
    end

    should "support sorting repositories" do
      repo_a = create(:repository, :with_commits, host: @host, owner: "owner1", full_name: "owner1/aaa", stargazers_count: 100)
      repo_z = create(:repository, :with_commits, host: @host, owner: "owner1", full_name: "owner1/zzz", stargazers_count: 200)
      
      get host_owner_path(@host.name, "owner1"), params: { sort: "full_name", order: "asc" }
      assert_response :success
      body = response.body
      assert body.index(repo_a.full_name) < body.index(repo_z.full_name)
      
      get host_owner_path(@host.name, "owner1"), params: { sort: "full_name", order: "desc" }
      assert_response :success
      body = response.body
      assert body.index(repo_z.full_name) < body.index(repo_a.full_name)
    end

    should "support multiple sort options" do
      # Make sure repositories are visible
      @owner1_repos.each { |r| r.update(last_synced_at: 1.hour.ago, total_commits: 100) }
      
      get host_owner_path(@host.name, "owner1"), params: { sort: "stargazers_count", order: "desc" }
      assert_response :success
    end

    should "default to last_synced_at DESC when no sort specified" do
      old_repo = create(:repository, :with_commits, host: @host, owner: "owner1", full_name: "owner1/old", last_synced_at: 1.week.ago)
      new_repo = create(:repository, :with_commits, host: @host, owner: "owner1", full_name: "owner1/new", last_synced_at: 1.hour.ago)
      
      get host_owner_path(@host.name, "owner1")
      assert_response :success
      body = response.body
      assert body.index(new_repo.full_name) < body.index(old_repo.full_name)
    end

    should "only show visible repositories" do
      # Make sure existing repos are visible first
      @owner1_repos.each { |r| r.update(last_synced_at: 1.hour.ago, total_commits: 100) }
      
      visible_repo = create(:repository, :with_commits, host: @host, owner: "owner1", full_name: "owner1/visible")
      invisible_repo = create(:repository, :not_synced, host: @host, owner: "owner1", full_name: "owner1/invisible")
      
      get host_owner_path(@host.name, "owner1")
      assert_response :success
      assert_match visible_repo.full_name, response.body
      assert_no_match invisible_repo.full_name, response.body
    end

    should "return 404 for non-existent host" do
      get host_owner_path("NonExistentHost", "owner1")
      assert_response :not_found
    end

    should "return 404 for owner with no repositories" do
      get host_owner_path(@host.name, "nonexistent-owner")
      assert_response :not_found
    end

    should "handle owners with special characters in name" do
      special_owner = "special-owner.with_chars"
      create(:repository, :with_commits, host: @host, owner: special_owner, full_name: "#{special_owner}/repo")
      
      get host_owner_path(@host.name, special_owner)
      assert_response :success
      assert_match special_owner, response.body
    end

    should "support pagination" do
      150.times { |i| create(:repository, :with_commits, host: @host, owner: "prolific-owner", full_name: "prolific-owner/repo#{i}") }
      
      get host_owner_path(@host.name, "prolific-owner")
      assert_response :success
      
      get host_owner_path(@host.name, "prolific-owner"), params: { page: 2 }
      assert_response :success
    end

    should "set proper cache headers" do
      # Make sure repositories are visible
      @owner1_repos.each { |r| r.update(last_synced_at: 1.hour.ago, total_commits: 100) }
      
      get host_owner_path(@host.name, "owner1")
      assert_response :success
      assert response.headers["Cache-Control"].present?
    end

    should "include owner statistics in title" do
      # Make sure repositories are visible
      @owner1_repos.each { |r| r.update(last_synced_at: 1.hour.ago, total_commits: 100) }
      
      get host_owner_path(@host.name, "owner1")
      assert_response :success
      assert_select "title", text: /owner1/
    end
  end
end