require "test_helper"

class HostTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:repositories)
  end

  context 'validations' do
    should validate_presence_of(:url)
    should validate_presence_of(:name)
    should validate_presence_of(:kind)
    should validate_uniqueness_of(:name)
  end
end
