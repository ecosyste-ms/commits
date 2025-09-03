FactoryBot.define do
  factory :export do
    sequence(:date) { |n| (Date.today - n.days).to_s }
    bucket_name { "ecosystems-commits" }
    commits_count { 1000000 }
    
    trait :latest do
      date { Date.today.to_s }
      commits_count { 2000000 }
    end
    
    trait :old do
      date { 30.days.ago.to_date.to_s }
      commits_count { 500000 }
    end
  end
end