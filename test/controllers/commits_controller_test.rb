require "test_helper"

class CommitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, :github)
    @repository = create(:repository, host: @host)
    @commit = create(:commit, repository: @repository)
  end

  test "should get index" do
    get host_repository_commits_url(@host, @repository)
    assert_response :success
  end

  test "should display commits" do
    get host_repository_commits_url(@host, @repository)
    assert_response :success
    assert_select "h1", text: /commits/
  end

  test "should handle repository without commits" do
    empty_repo = create(:repository, host: @host, full_name: "test/empty")
    get host_repository_commits_url(@host, empty_repo)
    assert_response :success
    assert_select "p.text-muted", text: /No commits found/
  end

  test "should paginate commits" do
    # Create more commits for pagination test
    30.times do |i|
      create(:commit, 
        repository: @repository,
        message: "Test commit #{i}",
        timestamp: i.days.ago
      )
    end
    
    get host_repository_commits_url(@host, @repository)
    assert_response :success
  end

  test "should handle since parameter" do
    get host_repository_commits_url(@host, @repository, since: 1.week.ago)
    assert_response :success
  end

  test "should handle until parameter" do
    get host_repository_commits_url(@host, @repository, until: 1.day.ago)
    assert_response :success
  end

  test "should handle sort and order parameters" do
    get host_repository_commits_url(@host, @repository, sort: 'timestamp', order: 'asc')
    assert_response :success
  end

  test "should display co-authors and signed-off-by when present" do
    message_with_metadata = "Fix critical bug\n\nCo-authored-by: Jane Doe <jane@example.com>\nCo-authored-by: Bob Smith <bob@example.com>\nSigned-off-by: Alice Johnson <alice@example.com>"
    
    create(:commit, 
      repository: @repository,
      message: message_with_metadata,
      timestamp: 1.hour.ago
    )
    
    get host_repository_commits_url(@host, @repository)
    assert_response :success
    assert_select "small.text-muted", text: /Co-authored-by:/
    assert_select "small.text-muted", text: /Signed-off-by:/
  end
end