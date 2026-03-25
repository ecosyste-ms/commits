require 'test_helper'

class OwnerTest < ActiveSupport::TestCase
  setup do
    @host = create(:host, :github)
  end

  test "requires login" do
    owner = Owner.new(host: @host, login: nil)
    assert_not owner.valid?
  end

  test "hidden defaults to false" do
    owner = Owner.create!(host: @host, login: "testowner")
    assert_equal false, owner.hidden
  end

  test "can be set to hidden" do
    owner = Owner.create!(host: @host, login: "testowner")
    assert_equal false, owner.hidden
    owner.update!(hidden: true)
    assert_equal true, owner.hidden
  end

  test "visible scope excludes hidden owners" do
    visible_owner = Owner.create!(host: @host, login: "visible", hidden: false)
    hidden_owner = Owner.create!(host: @host, login: "hidden", hidden: true)

    visible_owners = Owner.visible
    assert_includes visible_owners, visible_owner
    assert_not_includes visible_owners, hidden_owner
  end

  test "hidden scope only includes hidden owners" do
    visible_owner = Owner.create!(host: @host, login: "visible", hidden: false)
    hidden_owner = Owner.create!(host: @host, login: "hidden", hidden: true)

    hidden_owners = Owner.hidden
    assert_includes hidden_owners, hidden_owner
    assert_not_includes hidden_owners, visible_owner
  end

  test "unique login per host" do
    Owner.create!(host: @host, login: "testowner")
    duplicate = Owner.new(host: @host, login: "testowner")
    assert_not duplicate.valid?
  end
end
