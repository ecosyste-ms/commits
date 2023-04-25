class AddIconUrlToHosts < ActiveRecord::Migration[7.0]
  def change
    add_column :hosts, :icon_url, :string
  end
end
