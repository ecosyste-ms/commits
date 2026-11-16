if @owner.present?
  title = "#{@host} : #{@owner} repositories"
  feed_url = feed_host_owner_url(@host, @owner)
  html_url = host_owner_url(@host, @owner)
else
  title = "#{@host} repositories"
  feed_url = feed_host_repositories_url(@host)
  html_url = host_url(@host)
end

atom_feed(language: 'en-US', id: feed_url, root_url: html_url) do |feed|
  feed.title "#{title} | Ecosyste.ms: Commits"
  feed.subtitle "Recently synced repositories#{" owned by #{@owner}" if @owner.present?} on #{@host} that have had their commit history parsed"
  feed.updated @repositories.map(&:last_synced_at).compact.max
  feed.author { |author| author.name 'Ecosyste.ms' }

  feed.link rel: 'previous', type: 'application/atom+xml', href: pagy_url_for(@pagy, @pagy.prev, absolute: true) if @pagy.prev
  feed.link rel: 'next', type: 'application/atom+xml', href: pagy_url_for(@pagy, @pagy.next, absolute: true) if @pagy.next

  @repositories.each do |repository|
    feed.entry(repository, url: host_repository_url(@host, repository), updated: repository.last_synced_at) do |entry|
      entry.title repository.full_name
      entry.content type: 'html' do |content|
        content.text! safe_join([
          (content_tag(:p, repository.description) if repository.description.present?),
          (content_tag(:p, "Branch: #{repository.default_branch}") if repository.default_branch.present?),
          content_tag(:p, "Total Commits: #{number_with_delimiter repository.total_commits}"),
          content_tag(:p, "Total Committers: #{number_with_delimiter repository.total_committers}"),
          content_tag(:p, "Avg Commits per committer: #{number_with_delimiter repository.mean_commits&.round(3)}"),
          content_tag(:p, "Development Distribution Score (DDS): #{repository.dds&.round(3)}")
        ].compact)
      end
    end
  end
end
