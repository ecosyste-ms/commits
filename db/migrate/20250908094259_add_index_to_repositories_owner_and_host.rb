class AddIndexToRepositoriesOwnerAndHost < ActiveRecord::Migration[8.0]
  def change
    add_index :repositories, [:host_id, :owner]
  end
end
