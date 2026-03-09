json.extract! @committer, :id, :login, :emails, :commits_count, :created_at, :updated_at, :repositories_count

json.repositories @contributions do |contribution|
  json.extract! contribution.repository, :id, :full_name
  json.commit_count contribution.commit_count
end