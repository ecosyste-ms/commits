json.extract! host, :name, :url, :kind, :last_synced_at, :repositories_count, :commits_count, :contributors_count, :owners_count, :icon_url
json.host_url api_v1_host_url(host)
json.repositories_url api_v1_host_repositories_url(host)