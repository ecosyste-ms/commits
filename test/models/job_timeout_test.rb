require "test_helper"

class JobTimeoutTest < ActiveSupport::TestCase
  def setup
    @job = Job.create!(url: "https://github.com/test/repo", status: "pending")
  end

  test "perform_commit_parsing times out after 15 minutes" do
    # Mock parse_commits to raise timeout
    @job.stubs(:parse_commits).raises(Timeout::Error)
    Rails.logger.expects(:error).with("Job #{@job.id} timeout after 15 minutes for URL: #{@job.url}")
    
    @job.perform_commit_parsing
    
    @job.reload
    assert_equal "error", @job.status
    assert_equal "Timeout after 15 minutes", @job.results["error"]
  end

  test "perform_commit_parsing completes successfully within timeout" do
    test_results = { 
      full_name: "test/repo",
      total_commits: 100,
      committers: []
    }
    
    @job.stubs(:parse_commits).returns(test_results)
    
    @job.perform_commit_parsing
    
    @job.reload
    assert_equal "complete", @job.status
    assert_equal test_results, @job.results.symbolize_keys
  end

  test "perform_commit_parsing handles other errors properly" do
    error_message = "Something went wrong"
    
    @job.stubs(:parse_commits).raises(StandardError, error_message)
    
    @job.perform_commit_parsing
    
    @job.reload
    assert_equal "error", @job.status
    assert_includes @job.results["error"], error_message
  end
end