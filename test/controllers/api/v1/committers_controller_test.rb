require 'test_helper'

class Api::V1::CommittersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, :github)
    @committer = create(:committer, host: @host, login: "johndoe", commits_count: 500)
    @repo1 = create(:repository, :with_commits, host: @host)
    @repo2 = create(:repository, :with_commits, host: @host)
    @contribution1 = create(:contribution, committer: @committer, repository: @repo1, commit_count: 300)
    @contribution2 = create(:contribution, committer: @committer, repository: @repo2, commit_count: 200)
  end

  context "GET #show" do
    should "return success" do
      get api_v1_host_committer_path(@host.name, @committer.login)
      assert_response :success
    end

    should "return committer data with repositories count" do
      get api_v1_host_committer_path(@host.name, @committer.login)
      json = JSON.parse(response.body)
      assert_equal @committer.login, json["login"]
      assert_equal @committer.commits_count, json["commits_count"]
      assert_equal 2, json["repositories_count"]
    end

    should "return repositories ordered by commit count" do
      get api_v1_host_committer_path(@host.name, @committer.login)
      json = JSON.parse(response.body)
      repos = json["repositories"]
      assert_equal 2, repos.length
      assert_equal @repo1.full_name, repos[0]["full_name"]
      assert_equal 300, repos[0]["commit_count"]
      assert_equal @repo2.full_name, repos[1]["full_name"]
      assert_equal 200, repos[1]["commit_count"]
    end

    should "redirect when finding by email" do
      get api_v1_host_committer_path(@host.name, @committer.emails.first)
      assert_response :moved_permanently
    end

    should "return 404 for non-existent committer" do
      get api_v1_host_committer_path(@host.name, "nonexistent")
      assert_response :not_found
    end
  end
end
