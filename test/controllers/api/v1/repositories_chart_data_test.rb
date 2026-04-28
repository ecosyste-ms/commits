require 'test_helper'

class ApiV1RepositoriesChartDataTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @repository = @host.repositories.create!(full_name: 'ecosyste-ms/charts', last_synced_at: Time.current, total_commits: 3, total_committers: 2)
  end

  test 'returns commit count chart data' do
    create(:commit, repository: @repository, timestamp: Date.new(2026, 1, 10), author: 'Alice <alice@example.com>')
    create(:commit, repository: @repository, timestamp: Date.new(2026, 1, 20), author: 'Bob <bob@example.com>')
    create(:commit, repository: @repository, timestamp: Date.new(2026, 2, 1), author: 'Alice <alice@example.com>')

    get chart_data_api_v1_host_repository_path(@host, @repository.full_name), params: {
      chart: 'commits', period: 'month', start_date: '2026-01-01', end_date: '2026-02-28'
    }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 2, data['2026-01-01']
    assert_equal 1, data['2026-02-01']
  end

  test 'returns distinct committer chart data' do
    create(:commit, repository: @repository, timestamp: Date.new(2026, 1, 10), author: 'Alice <alice@example.com>')
    create(:commit, repository: @repository, timestamp: Date.new(2026, 1, 20), author: 'Alice <alice@example.com>')
    create(:commit, repository: @repository, timestamp: Date.new(2026, 1, 25), author: 'Bob <bob@example.com>')

    get chart_data_api_v1_host_repository_path(@host, @repository.full_name), params: {
      chart: 'committers', period: 'month', start_date: '2026-01-01', end_date: '2026-01-31'
    }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 2, data['2026-01-01']
  end

  test 'returns average commits per committer chart data' do
    create(:commit, repository: @repository, timestamp: Date.new(2026, 1, 10), author: 'Alice <alice@example.com>')
    create(:commit, repository: @repository, timestamp: Date.new(2026, 1, 20), author: 'Alice <alice@example.com>')
    create(:commit, repository: @repository, timestamp: Date.new(2026, 1, 25), author: 'Bob <bob@example.com>')

    get chart_data_api_v1_host_repository_path(@host, @repository.full_name), params: {
      chart: 'average_commits_per_committer', period: 'month', start_date: '2026-01-01', end_date: '2026-01-31'
    }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1.5, data['2026-01-01']
  end

  test 'returns bad request for unknown chart' do
    get chart_data_api_v1_host_repository_path(@host, @repository.full_name), params: { chart: 'unknown' }

    assert_response :bad_request
    assert_equal 'unknown chart', JSON.parse(response.body)['error']
  end
end
