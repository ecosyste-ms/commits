FactoryBot.define do
  factory :commit do
    repository
    sequence(:sha) { |n| "abc123def456ghi789jkl#{n}" }
    message { "Test commit message" }
    timestamp { 1.day.ago }
    author { "Test Author <test@example.com>" }
    committer { "Test Committer <test@example.com>" }
    stats { [3, 150, 20] }
    merge { false }
  end
end