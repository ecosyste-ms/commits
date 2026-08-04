class AddHostUpdatedAtIndexToCommitters < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :committers, [:host_id, :updated_at],
              order: { updated_at: :desc },
              where: "commits_count > 0",
              name: "index_committers_on_host_id_updated_at",
              algorithm: :concurrently
  end
end
