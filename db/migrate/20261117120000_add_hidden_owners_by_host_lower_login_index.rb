class AddHiddenOwnersByHostLowerLoginIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :owners, 'host_id, lower(login)',
              where: 'hidden = true',
              name: 'index_owners_hidden_by_host_lower_login',
              algorithm: :concurrently
  end
end
