class MakeCommittersHostIdLoginUnique < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :committers, [:host_id, :login],
              unique: true,
              name: 'index_committers_on_host_id_and_login_unique',
              algorithm: :concurrently
    remove_index :committers, name: 'index_committers_on_host_id_and_login', algorithm: :concurrently
    rename_index :committers, 'index_committers_on_host_id_and_login_unique', 'index_committers_on_host_id_and_login'
  end

  def down
    add_index :committers, [:host_id, :login],
              name: 'index_committers_on_host_id_and_login_old',
              algorithm: :concurrently
    remove_index :committers, name: 'index_committers_on_host_id_and_login', algorithm: :concurrently
    rename_index :committers, 'index_committers_on_host_id_and_login_old', 'index_committers_on_host_id_and_login'
  end
end
