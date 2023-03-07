class AddRepositoriesCountToHosts < ActiveRecord::Migration[7.0]
  def change
    add_column :hosts, :repositories_count, :integer
    add_column :hosts, :commits_count, :bigint
    add_column :hosts, :contributors_count, :bigint
  end
end
