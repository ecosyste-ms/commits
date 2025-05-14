class AddSizeToRepositories < ActiveRecord::Migration[8.0]
  def change
    add_column :repositories, :size, :integer
  end
end
