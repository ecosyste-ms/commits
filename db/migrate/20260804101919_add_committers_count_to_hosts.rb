class AddCommittersCountToHosts < ActiveRecord::Migration[8.1]
  def change
    add_column :hosts, :committers_count, :bigint, default: 0
  end
end
