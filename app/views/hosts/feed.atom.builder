atom_feed(language: 'en-US', id: feed_hosts_url, root_url: hosts_url) do |feed|
  feed.title "Repository Hosts | Ecosyste.ms: Commits"
  feed.subtitle "List of repository hosts that have had their commit history parsed"
  feed.updated @hosts.map(&:updated_at).compact.max
  feed.author { |author| author.name 'Ecosyste.ms' }

  @hosts.each do |host|
    feed.entry(host, url: host_url(host)) do |entry|
      entry.title host.name
      entry.content type: 'html' do |content|
        content << content_tag(:p, "Kind: #{host.kind}") if host.kind.present?
        content << content_tag(:p, "Repositories: #{number_with_delimiter host.repositories_count}")
        content << content_tag(:p, "Commits: #{number_with_delimiter host.commits_count}")
        content << content_tag(:p, "Committers: #{number_with_delimiter host.contributors_count}")
        content << content_tag(:p, "Owners: #{number_with_delimiter host.owners_count}")
      end
    end
  end
end
