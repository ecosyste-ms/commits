class CreateContributions < ActiveRecord::Migration[8.0]
  def change
    create_table :contributions do |t|
      t.references :committer, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.integer :commit_count

      t.timestamps
    end
  end
end
