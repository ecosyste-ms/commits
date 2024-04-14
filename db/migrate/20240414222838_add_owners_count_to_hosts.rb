class AddOwnersCountToHosts < ActiveRecord::Migration[7.1]
  def change
    add_column :hosts, :owners_count, :bigint, default: 0
  end
end
