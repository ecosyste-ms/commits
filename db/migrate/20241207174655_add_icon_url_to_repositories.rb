class AddIconUrlToRepositories < ActiveRecord::Migration[8.0]
  def change
    add_column :repositories, :icon_url, :string
  end
end
