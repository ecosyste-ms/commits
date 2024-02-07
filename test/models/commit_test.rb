require "test_helper"

class CommitTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
  end

  context 'validations' do
    should validate_presence_of(:sha)
    should validate_uniqueness_of(:sha).scoped_to(:repository_id)
  end
end
