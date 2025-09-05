class AddCoAuthorEmailToCommits < ActiveRecord::Migration[8.0]
  def change
    add_column :commits, :co_author_email, :string
    add_index :commits, :co_author_email, where: "co_author_email IS NOT NULL"
  end
end
