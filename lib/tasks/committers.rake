namespace :committers do
  desc 'merge duplicate committers with the same host_id and login'
  task dedupe: :environment do
    merged = Committer.dedupe
    puts "committers:dedupe done, #{merged} duplicate rows removed"
  end

  desc 'backfill committers.emails from repositories.committers JSON'
  task backfill_emails: :environment do
    batch = (ENV['BATCH'] || 1000).to_i
    updated = Committer.backfill_emails_from_repositories(batch_size: batch)
    puts "committers:backfill_emails done, #{updated} committers updated"
  end
end
