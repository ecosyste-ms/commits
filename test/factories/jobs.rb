FactoryBot.define do
  factory :job do
    url { "https://github.com/rails/rails" }
    sidekiq_id { SecureRandom.hex(12) }
    status { "pending" }
    ip { "127.0.0.1" }
    results { {} }
    
    trait :queued do
      status { "queued" }
    end
    
    trait :working do
      status { "working" }
    end
    
    trait :complete do
      status { "complete" }
      results { { commits_count: 100, repository_id: 1 } }
    end
    
    trait :error do
      status { "error" }
      results { { error: "Failed to parse commits" } }
    end
  end
end