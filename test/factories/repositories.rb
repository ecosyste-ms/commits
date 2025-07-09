FactoryBot.define do
  factory :repository do
    host
    sequence(:full_name) { |n| "owner#{n}/repo#{n}" }
    description { "A sample repository" }
    default_branch { "main" }
    stargazers_count { 100 }
    fork { false }
    archived { false }
    size { 5000 }
    last_synced_at { 1.hour.ago }
    status { nil }
    
    trait :with_commits do
      total_commits { 500 }
      total_committers { 10 }
      total_bot_commits { 50 }
      total_bot_committers { 2 }
      mean_commits { 50.0 }
      dds { 0.85 }
      committers do
        [
          { "name" => "John Doe", "email" => "john@example.com", "login" => "johndoe", "count" => 150 },
          { "name" => "Jane Smith", "email" => "jane@example.com", "login" => "janesmith", "count" => 100 },
          { "name" => "Bot User[bot]", "email" => "bot@example.com", "login" => "botuser", "count" => 50 }
        ]
      end
    end
    
    trait :with_past_year_commits do
      with_commits
      past_year_total_commits { 200 }
      past_year_total_committers { 5 }
      past_year_total_bot_commits { 20 }
      past_year_total_bot_committers { 1 }
      past_year_mean_commits { 40.0 }
      past_year_dds { 0.80 }
      past_year_committers do
        [
          { "name" => "John Doe", "email" => "john@example.com", "login" => "johndoe", "count" => 80 },
          { "name" => "Jane Smith", "email" => "jane@example.com", "login" => "janesmith", "count" => 60 }
        ]
      end
    end
    
    trait :not_synced do
      last_synced_at { nil }
      total_commits { nil }
      committers { nil }
    end
    
    trait :too_large do
      status { "too_large" }
      size { 600_000 }
    end
    
    trait :not_found do
      status { "not_found" }
    end
    
    trait :forked do
      fork { true }
    end
    
    trait :archived do
      archived { true }
    end
  end
end