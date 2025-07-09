FactoryBot.define do
  factory :contribution do
    committer
    repository
    commit_count { 50 }
    
    trait :high_contribution do
      commit_count { 500 }
    end
    
    trait :low_contribution do
      commit_count { 1 }
    end
  end
end