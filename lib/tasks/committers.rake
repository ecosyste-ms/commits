namespace :committers do
  desc 'merge duplicate committers with the same host_id and login'
  task dedupe: :environment do
    merged = Committer.dedupe
    puts "committers:dedupe done, #{merged} duplicate rows removed"
  end

  desc 'backfill committers.emails from repositories.committers JSON'
  task backfill_emails: :environment do
    batch = ENV['BATCH'].to_i
    batch = 1000 if batch <= 0
    updated = Committer.backfill_emails_from_repositories(batch_size: batch)
    puts "committers:backfill_emails done, #{updated} committers updated"
  end
end
