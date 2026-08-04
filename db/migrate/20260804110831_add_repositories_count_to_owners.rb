class AddRepositoriesCountToOwners < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :owners, :repositories_count, :bigint, default: 0
    add_index :owners, [:host_id, :repositories_count],
              order: { repositories_count: :desc },
              name: "index_owners_on_host_id_and_repositories_count",
              algorithm: :concurrently
  end
end
