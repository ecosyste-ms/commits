class AddHiddenCommittersByHostIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :committers, :host_id,
              where: 'hidden = true',
              name: 'index_committers_hidden_by_host',
              algorithm: :concurrently
  end
end
