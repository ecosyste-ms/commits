FactoryBot.define do
  factory :committer do
    host
    sequence(:login) { |n| "user#{n}" }
    emails { ["#{login}@example.com"] }
    commits_count { 100 }
    
    trait :with_multiple_emails do
      emails { ["#{login}@example.com", "#{login}@work.com", "#{login}@personal.com"] }
    end
    
    trait :no_login do
      login { nil }
      sequence(:emails) { |n| ["anonymous#{n}@example.com"] }
    end
    
    trait :bot do
      sequence(:login) { |n| "bot#{n}[bot]" }
      emails { ["#{login}@users.noreply.github.com"] }
    end
    
    trait :high_contributor do
      commits_count { 1000 }
    end
    
    trait :low_contributor do
      commits_count { 1 }
    end
  end
end