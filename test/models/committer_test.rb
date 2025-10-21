require "test_helper"

class CommitterTest < ActiveSupport::TestCase
  test "hidden defaults to false" do
    committer = create(:committer)
    assert_equal false, committer.hidden
  end

  test "hidden can be set to true" do
    committer = create(:committer, hidden: true)
    assert_equal true, committer.hidden
  end

  test "hidden can be set to false explicitly" do
    committer = create(:committer, hidden: false)
    assert_equal false, committer.hidden
  end
end
