class AddStatusFieldsToHosts < ActiveRecord::Migration[8.0]
  def change
    add_column :hosts, :status, :string, default: 'pending'
    add_column :hosts, :online, :boolean, default: true
    add_column :hosts, :status_checked_at, :datetime
    add_column :hosts, :response_time, :float
    add_column :hosts, :last_error, :text
    add_column :hosts, :can_crawl_api, :boolean, default: true
    add_column :hosts, :host_url, :text
    add_column :hosts, :repositories_url, :text
    add_column :hosts, :owners_url, :text
  end
end
