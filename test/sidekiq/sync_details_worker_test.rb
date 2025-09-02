require "test_helper"

class SyncDetailsWorkerTest < ActiveSupport::TestCase
  def setup
    @host = Host.create!(name: "github.com", url: "https://github.com", kind: "github")
    @repository = Repository.create!(
      host: @host,
      full_name: "test/repo",
      owner: "test"
    )
  end

  test "calls sync_details on repository" do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/hosts/github.com/repositories/test/repo")
      .to_return(status: 200, body: {
        status: 'active',
        default_branch: 'main',
        description: 'Test repo',
        stargazers_count: 10,
        fork: false
      }.to_json, headers: {'Content-Type' => 'application/json'})
    
    SyncDetailsWorker.new.perform(@repository.id)
    
    assert_requested :get, "https://repos.ecosyste.ms/api/v1/hosts/github.com/repositories/test/repo"
  end

  test "returns early if repository not found" do
    Repository.expects(:find_by_id).with(999999).returns(nil)
    
    assert_nothing_raised do
      SyncDetailsWorker.new.perform(999999)
    end
  end

  test "perform_async enqueues to regular queue by default" do
    Sidekiq::Client.expects(:push).with(
      'class' => SyncDetailsWorker,
      'queue' => 'sync_details',
      'args' => [@repository.id, false]
    )
    
    SyncDetailsWorker.perform_async(@repository.id)
  end

  test "perform_async enqueues to high priority queue when specified" do
    Sidekiq::Client.expects(:push).with(
      'class' => SyncDetailsWorker,
      'queue' => 'sync_details_high_priority',
      'args' => [@repository.id, true]
    )
    
    SyncDetailsWorker.perform_async(@repository.id, true)
  end
end