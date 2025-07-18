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
