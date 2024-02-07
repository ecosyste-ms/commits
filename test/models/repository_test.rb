require "test_helper"

class RepositoryTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:host)
    should have_many(:commits)
  end

  context 'validations' do
    should validate_presence_of(:full_name)
  end
end
