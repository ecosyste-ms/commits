class AddIndexToCommittersLogin < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  
  def change
    remove_index :committers, :host_id, algorithm: :concurrently
    add_index :committers, [:host_id, :login], algorithm: :concurrently
  end
end
