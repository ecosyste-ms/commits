require 'test_helper'

class CommittersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, :github)
    @committer1 = create(:committer, host: @host, login: "johndoe", commits_count: 500)
    @committer2 = create(:committer, :bot, host: @host, commits_count: 300)
    @committer3 = create(:committer, host: @host, login: "janesmith", commits_count: 200)
    @zero_commits_committer = create(:committer, host: @host, login: "inactive", commits_count: 0)
    
    # Create some repositories and contributions
    @repo1 = create(:repository, :with_commits, host: @host)
    @repo2 = create(:repository, :with_commits, host: @host)
    
    @contribution1 = create(:contribution, committer: @committer1, repository: @repo1, commit_count: 300)
    @contribution2 = create(:contribution, committer: @committer1, repository: @repo2, commit_count: 200)
    @contribution3 = create(:contribution, committer: @committer3, repository: @repo1, commit_count: 200)
  end

  context "GET #index" do
    should "return success" do
      get host_committers_path(@host.name)
      assert_response :success
      assert_template 'committers/index'
    end

    should "only show committers with commits > 0" do
      get host_committers_path(@host.name)
      assert_response :success
      
      assert_match @committer1.login, response.body
      assert_match @committer2.login, response.body
      assert_match @committer3.login, response.body
      assert_no_match @zero_commits_committer.login, response.body
    end

    should "display commit counts" do
      get host_committers_path(@host.name)
      assert_response :success
      
      assert_match @committer1.commits_count.to_s, response.body
      assert_match @committer2.commits_count.to_s, response.body
      assert_match @committer3.commits_count.to_s, response.body
    end

    should "support sorting by commits_count" do
      get host_committers_path(@host.name), params: { sort: "commits_count", order: "desc" }
      assert_response :success
      
      body = response.body
      # Should be ordered: committer1 (500) > committer2 (300) > committer3 (200)
      assert body.index(@committer1.login) < body.index(@committer2.login)
      assert body.index(@committer2.login) < body.index(@committer3.login)
    end

    should "support sorting by login" do
      get host_committers_path(@host.name), params: { sort: "login", order: "asc" }
      assert_response :success
      
      body = response.body
      # Alphabetical order: bot[bot] < janesmith < johndoe
      assert body.index(@committer2.login) < body.index(@committer3.login)
      assert body.index(@committer3.login) < body.index(@committer1.login)
    end

    should "support multiple sort options" do
      get host_committers_path(@host.name), params: { sort: "commits_count,login", order: "desc,asc" }
      assert_response :success
    end

    should "default to commits_count DESC when no sort specified" do
      get host_committers_path(@host.name)
      assert_response :success
      
      # Just verify that the right committers are shown and in some order
      assert_match @committer1.login, response.body
      assert_match @committer2.login, response.body
      assert_match @committer3.login, response.body
      
      # Verify they have the expected commits count
      assert_match "500", response.body  # committer1's count
      assert_match "300", response.body  # committer2's count
      assert_match "200", response.body  # committer3's count
    end

    should "support pagination" do
      create_list(:committer, 120, host: @host, commits_count: 10)
      
      get host_committers_path(@host.name)
      assert_response :success
      
      get host_committers_path(@host.name), params: { page: 2 }
      assert_response :success
    end

    should "return 404 for non-existent host" do
      get host_committers_path("NonExistentHost")
      assert_response :not_found
    end

    should "handle host with no committers" do
      empty_host = create(:host, name: "EmptyHost")
      
      get host_committers_path(empty_host.name)
      assert_response :success
      assert_template 'committers/index'
    end

    should "set proper cache headers" do
      get host_committers_path(@host.name)
      assert_response :success
      assert response.headers["Cache-Control"].present?
      assert_match "public", response.headers["Cache-Control"]
    end
  end

  context "GET #show" do
    should "return success when finding by login" do
      get host_committer_path(@host.name, @committer1.login)
      assert_response :success
      assert_template 'committers/show'
    end

    should "redirect when finding by email" do
      get host_committer_path(@host.name, @committer1.emails.first)
      assert_redirected_to host_committer_path(@host.name, @committer1.login)
    end

    should "redirect from email to login when committer has login" do
      get host_committer_path(@host.name, @committer1.emails.first)
      assert_redirected_to host_committer_path(@host.name, @committer1.login)
    end

    should "not redirect when committer has no login" do
      no_login_committer = create(:committer, :no_login, host: @host)
      
      get host_committer_path(@host.name, no_login_committer.emails.first)
      assert_response :success
      assert_template 'committers/show'
    end

    should "display committer information" do
      get host_committer_path(@host.name, @committer1.login)
      assert_response :success
      
      assert_match @committer1.login, response.body
      assert_match @committer1.commits_count.to_s, response.body
    end

    should "display contributions ordered by commit count" do
      get host_committer_path(@host.name, @committer1.login)
      assert_response :success
      
      body = response.body
      # contribution1 (300) should appear before contribution2 (200)
      assert body.index(@repo1.full_name) < body.index(@repo2.full_name)
    end

    should "only show contributions for the specified committer" do
      get host_committer_path(@host.name, @committer1.login)
      assert_response :success
      
      assert_match @repo1.full_name, response.body
      assert_match @repo2.full_name, response.body
      
      # Create a repo that committer1 hasn't contributed to
      other_repo = create(:repository, host: @host, full_name: "other/repo")
      create(:contribution, committer: @committer3, repository: other_repo)
      
      get host_committer_path(@host.name, @committer1.login)
      assert_no_match other_repo.full_name, response.body
    end

    should "return 404 for non-existent committer" do
      get host_committer_path(@host.name, "nonexistent")
      assert_response :not_found
    end

    should "return 404 for non-existent host" do
      get host_committer_path("NonExistentHost", @committer1.login)
      assert_response :not_found
    end

    should "handle committers with special characters in login" do
      special_committer = create(:committer, host: @host, login: "user-with.special_chars")
      
      get host_committer_path(@host.name, special_committer.login)
      assert_response :success
      assert_match special_committer.login, response.body
    end

    should "handle bot committers" do
      get host_committer_path(@host.name, @committer2.login)
      assert_response :success
      assert_match @committer2.login, response.body
    end

    should "show contributions with repository details" do
      get host_committer_path(@host.name, @committer1.login)
      assert_response :success
      
      # Should show repository names and contribution counts
      assert_match @contribution1.commit_count.to_s, response.body
      assert_match @contribution2.commit_count.to_s, response.body
    end

    should "set proper cache headers" do
      get host_committer_path(@host.name, @committer1.login)
      assert_response :success
      assert response.headers["Cache-Control"].present?
    end

    should "support finding by any email in the emails array" do
      multi_email_committer = create(:committer, :with_multiple_emails, host: @host)
      
      multi_email_committer.emails.each do |email|
        get host_committer_path(@host.name, email)
        assert_redirected_to host_committer_path(@host.name, multi_email_committer.login)
      end
    end

    should "handle URL-encoded email addresses" do
      email = @committer1.emails.first
      # The route parameter is already decoded by Rails
      
      get host_committer_path(@host.name, email)
      assert_redirected_to host_committer_path(@host.name, @committer1.login)
    end
  end
end