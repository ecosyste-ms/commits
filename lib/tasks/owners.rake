namespace :owners do
  desc 'cache visible repository counts per owner'
  task update_counts: :environment do
    Host.update_owner_counts
  end
end
