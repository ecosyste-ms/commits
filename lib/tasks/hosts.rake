namespace :hosts do
  desc 'update counts'
  task update_counts: :environment do
    Host.all.each(&:update_counts)
  end

  desc 'sync all'
  task sync_all: :environment do
    Host.sync_all
  end

  desc 'identify duplicate hosts with different cases'
  task identify_duplicates: :environment do
    duplicates = Host.all.group_by(&:name).transform_values(&:count).select { |_, count| count > 1 }
    case_duplicates = {}
    
    Host.all.each do |host|
      downcase_name = host.name.downcase
      case_duplicates[downcase_name] ||= []
      case_duplicates[downcase_name] << host
    end
    
    case_duplicates.select! { |_, hosts| hosts.size > 1 }
    
    puts "Found #{case_duplicates.size} host names with case variations:"
    case_duplicates.each do |downcase_name, hosts|
      puts "  #{downcase_name}:"
      hosts.each do |host|
        puts "    - #{host.name} (ID: #{host.id}, repos: #{host.repositories_count}, commits: #{host.commits_count})"
      end
    end
  end

  desc 'merge repositories and commits to downcased hosts'
  task merge_duplicates: :environment do
    case_duplicates = {}
    
    Host.all.each do |host|
      downcase_name = host.name.downcase
      case_duplicates[downcase_name] ||= []
      case_duplicates[downcase_name] << host
    end
    
    case_duplicates.select! { |_, hosts| hosts.size > 1 }
    
    case_duplicates.each do |downcase_name, hosts|
      # Find or create the target host (downcased)
      target_host = hosts.find { |h| h.name == downcase_name }
      unless target_host
        # Create a new host with the downcased name
        first_host = hosts.first
        target_host = Host.create!(
          name: downcase_name,
          url: first_host.url,
          kind: first_host.kind,
          icon_url: first_host.icon_url,
          last_synced_at: first_host.last_synced_at
        )
        puts "Created new target host: #{target_host.name}"
      end
      
      # Merge data from all other hosts to the target
      hosts.each do |host|
        next if host == target_host
        
        puts "Merging #{host.name} (ID: #{host.id}) into #{target_host.name} (ID: #{target_host.id})"
        
        # Move repositories
        host.repositories.each do |repo|
          begin
            repo.update!(host: target_host)
            puts "  Moved repository: #{repo.full_name}"
          rescue ActiveRecord::RecordInvalid => e
            puts "  Error moving repository #{repo.full_name}: #{e.message}"
          end
        end
        
        # Move committers
        host.committers.each do |committer|
          begin
            committer.update!(host: target_host)
            puts "  Moved committer: #{committer.login || committer.email}"
          rescue ActiveRecord::RecordInvalid => e
            puts "  Error moving committer #{committer.login || committer.email}: #{e.message}"
          end
        end
      end
      
      # Update counts for the target host
      target_host.update_counts
      puts "Updated counts for #{target_host.name}: repos=#{target_host.repositories_count}, commits=#{target_host.commits_count}"
    end
  end

  desc 'remove empty duplicate hosts after merge'
  task remove_duplicates: :environment do
    case_duplicates = {}
    
    Host.all.each do |host|
      downcase_name = host.name.downcase
      case_duplicates[downcase_name] ||= []
      case_duplicates[downcase_name] << host
    end
    
    case_duplicates.select! { |_, hosts| hosts.size > 1 }
    
    case_duplicates.each do |downcase_name, hosts|
      target_host = hosts.find { |h| h.name == downcase_name }
      
      hosts.each do |host|
        next if host == target_host
        
        # Only remove if empty
        if host.repositories.count == 0 && host.committers.count == 0
          puts "Removing empty host: #{host.name} (ID: #{host.id})"
          host.destroy
        else
          puts "Skipping non-empty host: #{host.name} (repos: #{host.repositories.count}, committers: #{host.committers.count})"
        end
      end
    end
  end

  desc 'force cleanup any remaining duplicates'
  task force_cleanup: :environment do
    case_duplicates = {}
    
    Host.all.each do |host|
      downcase_name = host.name.downcase
      case_duplicates[downcase_name] ||= []
      case_duplicates[downcase_name] << host
    end
    
    case_duplicates.select! { |_, hosts| hosts.size > 1 }
    
    case_duplicates.each do |downcase_name, hosts|
      target_host = hosts.find { |h| h.name == downcase_name }
      
      hosts.each do |host|
        next if host == target_host
        
        puts "Force removing host: #{host.name} (ID: #{host.id})"
        host.destroy
      end
    end
  end
end