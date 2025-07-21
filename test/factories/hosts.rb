FactoryBot.define do
  factory :host do
    sequence(:name) { |n| "Host#{n}" }
    url { "https://#{name.downcase}.com" }
    kind { "github" }
    icon_url { "https://#{name.downcase}.com/favicon.ico" }
    repositories_count { 10 }
    commits_count { 1000 }
    contributors_count { 50 }
    owners_count { 5 }
    status { 'ok' }
    online { true }
    can_crawl_api { true }
    status_checked_at { 1.hour.ago }
    response_time { 0.5 }
    
    trait :with_repositories do
      after(:create) do |host|
        create_list(:repository, 3, host: host)
      end
    end
    
    trait :invisible do
      repositories_count { 0 }
      commits_count { 0 }
    end
    
    trait :offline do
      online { false }
      status { 'error' }
      last_error { 'Connection timeout' }
    end
    
    trait :api_blocked do
      can_crawl_api { false }
      last_error { 'Blocked by robots.txt' }
    end
    
    trait :github do
      name { "GitHub" }
      url { "https://github.com" }
      kind { "github" }
    end
    
    trait :gitlab do
      name { "GitLab" }
      url { "https://gitlab.com" }
      kind { "gitlab" }
    end
  end
end