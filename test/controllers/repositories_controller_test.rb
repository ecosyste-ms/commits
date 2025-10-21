require 'test_helper'

class RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, :github)
    @repository = create(:repository, :with_commits, host: @host, full_name: 'ecosyste-ms/repos')
  end

  context "GET #index" do
    should "redirect to host show page" do
      get host_repositories_path(@host.name)
      assert_redirected_to host_path(@host)
    end

    should "redirect uppercase host names to lowercase" do
      get host_repositories_path(@host.name.upcase)
      assert_response :moved_permanently
      assert_redirected_to host_repositories_path(@host.name)
    end

    should "redirect mixed case host names to lowercase" do
      mixed_case_name = @host.name.split('.').map(&:capitalize).join('.')
      get host_repositories_path(mixed_case_name)
      assert_response :moved_permanently
      assert_redirected_to host_repositories_path(@host.name)
    end
  end

  context "GET #show" do
    should "return success for existing repository" do
      get host_repository_path(host_id: @host.name, id: @repository.full_name)
      assert_response :success
      assert_template 'repositories/show'
    end

    should "handle case-insensitive repository names" do
      get host_repository_path(host_id: @host.name, id: @repository.full_name.upcase)
      assert_response :success
    end

    should "return 404 for non-existent repository" do
      Host.any_instance.expects(:sync_repository_async).returns(nil)
      
      get host_repository_path(host_id: @host.name, id: "non/existent")
      assert_response :not_found
    end

    should "return 404 for non-existent host" do
      get host_repository_path(host_id: "NonExistent", id: @repository.full_name)
      assert_response :not_found
    end

    should "redirect uppercase host names to lowercase" do
      get host_repository_path(host_id: @host.name.upcase, id: @repository.full_name)
      assert_response :moved_permanently
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "redirect mixed case host names to lowercase" do
      mixed_case_name = @host.name.split('.').map(&:capitalize).join('.')
      get host_repository_path(host_id: mixed_case_name, id: @repository.full_name)
      assert_response :moved_permanently
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "sync repository if it doesn't exist" do
      new_repo_name = "owner/new-repo"
      Host.any_instance.expects(:sync_repository_async).with(new_repo_name, anything).once
      
      get host_repository_path(host_id: @host.name, id: new_repo_name)
      assert_response :not_found
    end

    should "display repository information" do
      get host_repository_path(host_id: @host.name, id: @repository.full_name)
      assert_response :success
      assert_match @repository.full_name, response.body
      assert_match @repository.description, response.body
    end

    should "display commit statistics" do
      get host_repository_path(host_id: @host.name, id: @repository.full_name)
      assert_response :success
      assert_match @repository.total_commits.to_s, response.body
      assert_match @repository.total_committers.to_s, response.body
    end

    should "handle repositories with special characters" do
      special_repo = create(:repository, host: @host, full_name: "owner/repo-with.special_chars")
      get host_repository_path(host_id: @host.name, id: special_repo.full_name)
      assert_response :success
    end

    should "set proper cache headers" do
      get host_repository_path(host_id: @host.name, id: @repository.full_name)
      assert_response :success
      assert response.headers["Cache-Control"].present?
    end

    should "hide committers where hidden is true" do
      # Create committer records matching the JSON data
      hidden_committer = create(:committer, host: @host, login: "johndoe", emails: ["john@example.com"], hidden: true)
      visible_committer = create(:committer, host: @host, login: "janesmith", emails: ["jane@example.com"], hidden: false)

      # Create contributions
      create(:contribution, repository: @repository, committer: hidden_committer, commit_count: 150)
      create(:contribution, repository: @repository, committer: visible_committer, commit_count: 100)

      get host_repository_path(host_id: @host.name, id: @repository.full_name)
      assert_response :success

      # Check that hidden committer is not in the response
      assert_not_includes assigns(:committers).map { |c| c['login'] }, "johndoe"
      # Check that visible committer is in the response
      assert_includes assigns(:committers).map { |c| c['login'] }, "janesmith"
    end

    should "hide committers by email when login is not present" do
      # Create a committer without login
      hidden_committer = create(:committer, host: @host, login: nil, emails: ["john@example.com"], hidden: true)
      create(:contribution, repository: @repository, committer: hidden_committer, commit_count: 150)

      get host_repository_path(host_id: @host.name, id: @repository.full_name)
      assert_response :success

      # Check that hidden committer is not in the response
      assert_not_includes assigns(:committers).map { |c| c['email'] }, "john@example.com"
    end

    should "hide past year committers where hidden is true" do
      repo = create(:repository, :with_past_year_commits, host: @host, full_name: "test/repo")

      # Create committer records matching the JSON data
      hidden_committer = create(:committer, host: @host, login: "johndoe", emails: ["john@example.com"], hidden: true)
      visible_committer = create(:committer, host: @host, login: "janesmith", emails: ["jane@example.com"], hidden: false)

      # Create contributions
      create(:contribution, repository: repo, committer: hidden_committer, commit_count: 80)
      create(:contribution, repository: repo, committer: visible_committer, commit_count: 60)

      get host_repository_path(host_id: @host.name, id: repo.full_name)
      assert_response :success

      # Check that hidden committer is not in the response
      assert_not_includes assigns(:past_year_committers).map { |c| c['login'] }, "johndoe"
      # Check that visible committer is in the response
      assert_includes assigns(:past_year_committers).map { |c| c['login'] }, "janesmith"
    end
  end

  context "GET #lookup" do
    should "redirect to repository for existing repository with https URL" do
      url = "https://github.com/#{@repository.full_name}"
      
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "redirect to repository for existing repository with git URL" do
      url = "git@github.com:#{@repository.full_name}.git"
      
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "handle URLs with .git suffix" do
      url = "https://github.com/#{@repository.full_name}.git"
      
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "handle URLs with trailing slash" do
      url = "https://github.com/#{@repository.full_name}/"
      
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "trigger sync for existing repository not synced recently" do
      @repository.update(last_synced_at: 2.days.ago)
      Repository.any_instance.expects(:sync_async).once
      
      url = "https://github.com/#{@repository.full_name}"
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "not trigger sync for recently synced repository" do
      @repository.update(last_synced_at: 30.minutes.ago)
      @repository.expects(:sync_async).never
      
      url = "https://github.com/#{@repository.full_name}"
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "return 404 and trigger sync for non-existent repository" do
      new_repo = "owner/new-repository"
      url = "https://github.com/#{new_repo}"
      
      Host.any_instance.expects(:sync_repository_async).with(new_repo, anything).once
      
      get lookup_repositories_path, params: { url: url }
      assert_response :not_found
    end

    should "handle case-insensitive lookups" do
      url = "https://github.com/#{@repository.full_name.upcase}"
      
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "return 404 for invalid URL" do
      get lookup_repositories_path, params: { url: "not-a-valid-url" }
      assert_response :not_found
    end

    should "return 404 for empty URL" do
      get lookup_repositories_path, params: { url: "" }
      assert_response :not_found
    end

    should "return 404 for URL with no path" do
      get lookup_repositories_path, params: { url: "https://github.com" }
      assert_response :not_found
    end

    should "return 404 for unknown host" do
      get lookup_repositories_path, params: { url: "https://unknown-host.com/repo/name" }
      assert_response :not_found
    end

    should "handle gitlab URLs" do
      gitlab_host = create(:host, :gitlab)
      gitlab_repo = create(:repository, host: gitlab_host, full_name: "group/project")
      
      url = "https://gitlab.com/group/project"
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(gitlab_host.name, gitlab_repo.full_name)
    end

    should "parse SSH URLs correctly" do
      url = "git@github.com:#{@repository.full_name}.git"
      
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "handle SSH URLs without .git suffix" do
      url = "git@github.com:#{@repository.full_name}"
      
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, @repository.full_name)
    end

    should "handle nested repository paths" do
      nested_repo = create(:repository, host: @host, full_name: "org/sub/project")
      url = "https://github.com/org/sub/project"
      
      get lookup_repositories_path, params: { url: url }
      assert_redirected_to host_repository_path(@host.name, nested_repo.full_name)
    end

    should "track remote IP for sync requests" do
      new_repo = "owner/tracking-test"
      url = "https://github.com/#{new_repo}"
      
      Host.any_instance.expects(:sync_repository_async).with(new_repo, anything).once
      
      get lookup_repositories_path, params: { url: url }
      assert_response :not_found
    end
  end
end