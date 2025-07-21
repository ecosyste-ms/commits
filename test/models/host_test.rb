require "test_helper"

class HostTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:repositories)
  end

  context 'validations' do
    should validate_presence_of(:url)
    should validate_presence_of(:name)
    should validate_presence_of(:kind)
    should validate_uniqueness_of(:name).case_insensitive
  end

  context 'status methods' do
    should 'return true for online? when online is true' do
      host = create(:host, online: true)
      assert host.online?
    end

    should 'return false for online? when online is false' do
      host = create(:host, online: false)
      assert_not host.online?
    end

    should 'return true for can_be_indexed? when online and can_crawl_api' do
      host = create(:host, online: true, can_crawl_api: true)
      assert host.can_be_indexed?
    end

    should 'return false for can_be_indexed? when offline' do
      host = create(:host, online: false, can_crawl_api: true)
      assert_not host.can_be_indexed?
    end

    should 'return false for can_be_indexed? when api blocked' do
      host = create(:host, online: true, can_crawl_api: false)
      assert_not host.can_be_indexed?
    end

    should 'return "Online" for status_display when online' do
      host = create(:host, online: true)
      assert_equal 'Online', host.status_display
    end

    should 'return "Offline" for status_display when offline' do
      host = create(:host, online: false)
      assert_equal 'Offline', host.status_display
    end
  end

  context 'scopes' do
    should 'return only indexable hosts in indexable scope' do
      indexable_host = create(:host, online: true, can_crawl_api: true)
      offline_host = create(:host, :offline)
      blocked_host = create(:host, :api_blocked)

      indexable_hosts = Host.indexable

      assert_includes indexable_hosts, indexable_host
      assert_not_includes indexable_hosts, offline_host
      assert_not_includes indexable_hosts, blocked_host
    end
  end

  context 'sync methods' do
    should 'not sync repositories when host cannot be indexed' do
      host = create(:host, :offline)
      
      result = host.sync_recently_updated_repositories_async
      
      assert_nil result
    end
  end

  context 'case insensitive uniqueness' do
    should 'not allow duplicate names with different cases' do
      host1 = Host.create!(name: 'github.com', url: 'https://github.com', kind: 'git')
      host2 = Host.new(name: 'GitHub.com', url: 'https://github.com', kind: 'git')
      
      assert_not host2.valid?
      assert_includes host2.errors[:name], 'has already been taken'
    end
    
    should 'not allow uppercase variations' do
      host1 = Host.create!(name: 'gitlab.com', url: 'https://gitlab.com', kind: 'git')
      host2 = Host.new(name: 'GitLab.com', url: 'https://gitlab.com', kind: 'git')
      
      assert_not host2.valid?
      assert_includes host2.errors[:name], 'has already been taken'
    end
    
    should 'not allow mixed case variations' do
      host1 = Host.create!(name: 'codeberg.org', url: 'https://codeberg.org', kind: 'git')
      host2 = Host.new(name: 'Codeberg.org', url: 'https://codeberg.org', kind: 'git')
      
      assert_not host2.valid?
      assert_includes host2.errors[:name], 'has already been taken'
    end
  end
end
