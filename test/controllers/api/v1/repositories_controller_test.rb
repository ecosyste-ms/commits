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

  test 'get a repository includes status when sync is skipped' do
    @repository.update!(status: 'too_large')

    get api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)

    assert_response :success
    assert_equal 'too_large', JSON.parse(@response.body)['status']
  end

  test 'get a repository returns accepted while it is pending' do
    repository = @host.repositories.create!(full_name: 'owner/pending-repo')

    get api_v1_host_repository_path(host_id: @host.name, id: repository.full_name)

    assert_response :accepted
    response_json = JSON.parse(response.body)
    assert_equal 'pending', response_json['status']
    assert_equal api_v1_host_repository_url(@host, repository), response_json['repository_url']
    assert_equal '60', response.headers['Retry-After']
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

  test 'lookup returns accepted for a repository that has not synced' do
    repository = @host.repositories.create!(full_name: 'owner/pending-repo')
    SyncRepositoryWorker.expects(:perform_async).with(repository.id).returns('job-id')

    get api_v1_repositories_lookup_path(url: 'https://github.com/owner/pending-repo')

    assert_response :accepted
    response_json = JSON.parse(response.body)
    assert_equal 'pending', response_json['status']
    assert_equal api_v1_host_repository_url(@host, repository), response_json['repository_url']
    assert_equal api_v1_host_repository_commits_url(@host, repository), response_json['commits_url']
    assert_equal '60', response.headers['Retry-After']
    assert_includes response.headers['Cache-Control'], 'no-store'
  end

  test 'lookup creates an unknown repository and returns accepted' do
    SyncRepositoryWorker.expects(:perform_async).with(kind_of(Integer)).returns('job-id')

    get api_v1_repositories_lookup_path(url: 'https://github.com/owner/new-repo')

    assert_response :accepted
    repository = @host.repositories.find_by!(full_name: 'owner/new-repo')
    assert_equal api_v1_host_repository_url(@host, repository), JSON.parse(response.body)['repository_url']
  end

  test 'lookup a repository using git@ SSH format' do
    get api_v1_repositories_lookup_path(url: 'git@github.com:ecosyste-ms/repos.git')
    assert_response :redirect
  end

  test 'lookup handles malformed SSH URL without colon' do
    get api_v1_repositories_lookup_path(url: 'git@github.com')
    assert_response :not_found
  end

  test 'lookup handles malformed SSH URL with empty path' do
    get api_v1_repositories_lookup_path(url: 'git@github.com:')
    assert_response :not_found
  end

  test 'get a repository with hidden owner returns 404' do
    Owner.create!(host: @host, login: 'ecosyste-ms', hidden: true)
    get api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :not_found
  end

  test 'lookup a repository with hidden owner returns 404' do
    Owner.create!(host: @host, login: 'ecosyste-ms', hidden: true)
    get api_v1_repositories_lookup_path(url: 'https://github.com/ecosyste-ms/repos/')
    assert_response :not_found
  end

  test 'lookup does not create a repository for a hidden owner' do
    Owner.create!(host: @host, login: 'hidden-owner', hidden: true)
    SyncRepositoryWorker.expects(:perform_async).never

    assert_no_difference -> { @host.repositories.count } do
      get api_v1_repositories_lookup_path(url: 'https://github.com/hidden-owner/new-repo')
    end

    assert_response :not_found
  end

  test 'API hides committers where hidden is true' do
    repo = create(:repository, :with_commits, host: @host, full_name: 'test/repo')

    # Create committer records matching the JSON data
    hidden_committer = create(:committer, host: @host, login: "johndoe", emails: ["john@example.com"], hidden: true)
    visible_committer = create(:committer, host: @host, login: "janesmith", emails: ["jane@example.com"], hidden: false)

    # Create contributions
    create(:contribution, repository: repo, committer: hidden_committer, commit_count: 150)
    create(:contribution, repository: repo, committer: visible_committer, commit_count: 100)

    get api_v1_host_repository_path(host_id: @host.name, id: repo.full_name)
    assert_response :success

    actual_response = JSON.parse(@response.body)

    # Check that hidden committer is not in the response
    assert_not_includes actual_response['committers'].map { |c| c['login'] }, "johndoe"
    # Check that visible committer is in the response
    assert_includes actual_response['committers'].map { |c| c['login'] }, "janesmith"
  end

  test 'API hides committers by email when login is not present' do
    repo = create(:repository, :with_commits, host: @host, full_name: 'test/repo2')

    # Create a committer without login
    hidden_committer = create(:committer, host: @host, login: nil, emails: ["john@example.com"], hidden: true)
    create(:contribution, repository: repo, committer: hidden_committer, commit_count: 150)

    get api_v1_host_repository_path(host_id: @host.name, id: repo.full_name)
    assert_response :success

    actual_response = JSON.parse(@response.body)

    # Check that hidden committer is not in the response
    assert_not_includes actual_response['committers'].map { |c| c['email'] }, "john@example.com"
  end

  test 'API hides past year committers where hidden is true' do
    repo = create(:repository, :with_past_year_commits, host: @host, full_name: 'test/repo3')

    # Create committer records matching the JSON data
    hidden_committer = create(:committer, host: @host, login: "johndoe", emails: ["john@example.com"], hidden: true)
    visible_committer = create(:committer, host: @host, login: "janesmith", emails: ["jane@example.com"], hidden: false)

    # Create contributions
    create(:contribution, repository: repo, committer: hidden_committer, commit_count: 80)
    create(:contribution, repository: repo, committer: visible_committer, commit_count: 60)

    get api_v1_host_repository_path(host_id: @host.name, id: repo.full_name)
    assert_response :success

    actual_response = JSON.parse(@response.body)

    # Check that hidden committer is not in the response
    assert_not_includes actual_response['past_year_committers'].map { |c| c['login'] }, "johndoe"
    # Check that visible committer is in the response
    assert_includes actual_response['past_year_committers'].map { |c| c['login'] }, "janesmith"
  end

  test 'ping does not create a repository for a hidden owner' do
    Owner.create!(host: @host, login: 'hidden-owner', hidden: true)
    SyncRepositoryWorker.expects(:perform_async).never

    assert_no_difference -> { @host.repositories.count } do
      get ping_api_v1_host_repository_path(host_id: @host.name, id: 'Hidden-Owner/new-repo')
    end

    assert_response :not_found
  end

  test 'ping with malformed full_name returns 404 and creates nothing' do
    assert_no_difference 'Repository.count' do
      get ping_api_v1_host_repository_path(host_id: @host.name, id: 'bareowner')
    end
    assert_response :not_found
  end

  test 'get a repository includes the charts url' do
    get api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)

    assert_response :success
    assert_equal charts_api_v1_host_repository_url(@host, @repository), JSON.parse(@response.body)['charts_url']
  end

  test 'charts returns monthly commit activity by default' do
    @repository.commits.create!(sha: 'a1', timestamp: Time.utc(2024, 1, 3), author: 'Alice <alice@example.com>')
    @repository.commits.create!(sha: 'a2', timestamp: Time.utc(2024, 1, 20), author: 'Alice <alice@example.com>')
    @repository.commits.create!(sha: 'b1', timestamp: Time.utc(2024, 1, 25), author: 'Bob <bob@example.com>')
    @repository.commits.create!(sha: 'b2', timestamp: Time.utc(2024, 3, 5), author: 'Bob <bob@example.com>')

    get charts_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)

    assert_response :success
    assert_template 'repositories/charts', file: 'repositories/charts.json.jbuilder'

    actual_response = JSON.parse(@response.body)

    assert_equal 'month', actual_response['period']
    assert_equal({ '2024-01-01' => 3, '2024-02-01' => 0, '2024-03-01' => 1 }, actual_response['commits'])
    assert_equal({ '2024-01-01' => 2, '2024-02-01' => 0, '2024-03-01' => 1 }, actual_response['committers'])
    assert_equal({ '2024-01-01' => 1.5, '2024-02-01' => 0, '2024-03-01' => 1.0 }, actual_response['average_commits_per_committer'])
  end

  test 'charts groups commit activity by the requested period' do
    @repository.commits.create!(sha: 'a1', timestamp: Time.utc(2023, 6, 1), author: 'Alice <alice@example.com>')
    @repository.commits.create!(sha: 'a2', timestamp: Time.utc(2024, 2, 1), author: 'Alice <alice@example.com>')

    get charts_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name, period: 'year')

    assert_response :success
    actual_response = JSON.parse(@response.body)
    assert_equal 'year', actual_response['period']
    assert_equal({ '2023-01-01' => 1, '2024-01-01' => 1 }, actual_response['commits'])
  end

  test 'charts falls back to monthly activity for an unknown period' do
    @repository.commits.create!(sha: 'a1', timestamp: Time.utc(2024, 1, 3), author: 'Alice <alice@example.com>')

    get charts_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name, period: 'fortnight')

    assert_response :success
    actual_response = JSON.parse(@response.body)
    assert_equal 'month', actual_response['period']
    assert_equal({ '2024-01-01' => 1 }, actual_response['commits'])
  end

  test 'charts filters commit activity by since and until' do
    @repository.commits.create!(sha: 'a1', timestamp: Time.utc(2024, 1, 3), author: 'Alice <alice@example.com>')
    @repository.commits.create!(sha: 'a2', timestamp: Time.utc(2024, 2, 3), author: 'Alice <alice@example.com>')
    @repository.commits.create!(sha: 'a3', timestamp: Time.utc(2024, 3, 3), author: 'Alice <alice@example.com>')

    get charts_api_v1_host_repository_path(
      host_id: @host.name,
      id: @repository.full_name,
      since: '2024-02-01T00:00:00Z',
      until: '2024-03-01T00:00:00Z'
    )

    assert_response :success
    assert_equal({ '2024-02-01' => 1 }, JSON.parse(@response.body)['commits'])
  end

  test 'charts returns empty series for a repository without stored commits' do
    get charts_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)

    assert_response :success
    actual_response = JSON.parse(@response.body)
    assert_equal({}, actual_response['commits'])
    assert_equal({}, actual_response['committers'])
    assert_equal({}, actual_response['average_commits_per_committer'])
  end

  test 'charts accepts an unescaped repository name' do
    @repository.commits.create!(sha: 'a1', timestamp: Time.utc(2024, 1, 3), author: 'Alice <alice@example.com>')

    get "/api/v1/hosts/#{@host.name}/repositories/#{@repository.full_name}/charts?period=year"

    assert_response :success
    assert_equal({ '2024-01-01' => 1 }, JSON.parse(@response.body)['commits'])
  end

  test 'charts finds a repository case insensitively' do
    @repository.commits.create!(sha: 'a1', timestamp: Time.utc(2024, 1, 3), author: 'Alice <alice@example.com>')

    get charts_api_v1_host_repository_path(host_id: @host.name, id: 'Ecosyste-MS/Repos')

    assert_response :success
    assert_equal({ '2024-01-01' => 1 }, JSON.parse(@response.body)['commits'])
  end

  test 'charts returns not modified for a matching etag' do
    get charts_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success

    get charts_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name),
      headers: { 'If-None-Match' => response.headers['ETag'] }

    assert_response :not_modified
  end

  test 'charts returns accepted while the repository is pending' do
    repository = @host.repositories.create!(full_name: 'owner/pending-repo')

    get charts_api_v1_host_repository_path(host_id: @host.name, id: repository.full_name)

    assert_response :accepted
    assert_equal 'pending', JSON.parse(response.body)['status']
    assert_equal '60', response.headers['Retry-After']
  end

  test 'charts returns 404 for an unknown repository' do
    assert_no_difference 'Repository.count' do
      get charts_api_v1_host_repository_path(host_id: @host.name, id: 'owner/unknown-repo')
    end

    assert_response :not_found
  end

  test 'charts returns 404 for a hidden owner' do
    Owner.create!(host: @host, login: 'ecosyste-ms', hidden: true)

    get charts_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)

    assert_response :not_found
  end

  test 'charts redirects mixed case host names to lowercase' do
    get charts_api_v1_host_repository_path(host_id: @host.name.upcase, id: @repository.full_name, period: 'year')

    assert_response :moved_permanently
    assert_redirected_to charts_api_v1_host_repository_path(@host.name, @repository.full_name, period: 'year')
  end

  test 'a repository named charts is still served by show' do
    repository = @host.repositories.create!(full_name: 'owner/charts', last_synced_at: Time.now, total_commits: 1, total_committers: 1)

    get "/api/v1/hosts/#{@host.name}/repositories/owner/charts"

    assert_response :success
    assert_equal 'owner/charts', JSON.parse(@response.body)['full_name']
  end
end
