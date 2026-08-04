class AddVisibleLastSyncedAtIndexToRepositories < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :repositories, :last_synced_at,
              order: { last_synced_at: :desc },
              where: "status IS NULL AND last_synced_at IS NOT NULL AND total_commits IS NOT NULL",
              name: "index_repositories_visible_last_synced_at",
              algorithm: :concurrently
  end
end
