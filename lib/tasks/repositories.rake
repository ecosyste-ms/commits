namespace :repositories do
  desc 'sync least recently synced repos'
  task sync_least_recent: :environment do
      Repository.sync_least_recently_synced
  end

  desc 'sync repos that have never produced a commit count'
  task sync_invisible: :environment do
      Repository.sync_invisible
  end
end
