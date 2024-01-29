class CreateCommits < ActiveRecord::Migration[7.1]
  def change
    create_table :commits do |t|
      t.integer :repository_id
      t.string :sha
      t.string :message
      t.datetime :timestamp
      t.boolean :merge
      t.string :author
      t.string :committer
      t.integer :stats, array: true, default: []

      t.timestamps
    end
    add_index :commits, [:repository_id, :sha]
  end
end
