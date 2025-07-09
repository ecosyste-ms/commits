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
    
    trait :with_repositories do
      after(:create) do |host|
        create_list(:repository, 3, host: host)
      end
    end
    
    trait :invisible do
      repositories_count { 0 }
      commits_count { 0 }
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