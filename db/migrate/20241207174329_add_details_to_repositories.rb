class AddDetailsToRepositories < ActiveRecord::Migration[8.0]
  def change
    add_column :repositories, :description, :string
    add_column :repositories, :stargazers_count, :integer
    add_column :repositories, :fork, :boolean
    add_column :repositories, :archived, :boolean
  end
end
