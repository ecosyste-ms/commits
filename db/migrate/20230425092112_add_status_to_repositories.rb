class AddStatusToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :status, :string
  end
end
