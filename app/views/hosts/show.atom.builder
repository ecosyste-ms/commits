atom_feed do |feed|
  feed.title "#{@host} repositories - commits.ecosyste.ms"
  feed.updated(@repositories.first&.last_synced_at || @host.updated_at || Time.current)

  @repositories.each do |repository|
    feed.entry(repository, url: host_repository_url(@host, repository)) do |entry|
      entry.title repository.full_name
      entry.updated repository.last_synced_at || repository.updated_at
      entry.summary "#{repository.full_name} has #{number_with_delimiter(repository.total_commits || 0)} commits from #{number_with_delimiter(repository.total_committers || 0)} committers."
      entry.author { |author| author.name @host.to_s }
    end
  end
end
