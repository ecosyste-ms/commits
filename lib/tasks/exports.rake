namespace :exports do
  desc 'Record export'
  task record: :environment do
    date = ENV['EXPORT_DATE'] || Date.today.strftime('%Y-%m-%d')
    bucket_name = ENV['BUCKET_NAME'] || 'ecosystems-data'
    Export.create!(date: date, bucket_name: bucket_name, commits_count: Host.visible.sum(&:commits_count))
  end
end