FactoryBot.define do
  factory :owner do
    host
    sequence(:login) { |n| "owner#{n}" }
    hidden { false }

    factory :hidden_owner do
      login { 'hiddenowner' }
      hidden { true }
    end
  end
end
