class AddLowerFullNameIndexToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_index :repositories, 'host_id, lower(full_name)', unique: true
  end
end
