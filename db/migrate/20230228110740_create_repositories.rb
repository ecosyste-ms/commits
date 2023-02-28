class CreateRepositories < ActiveRecord::Migration[7.0]
  def change
    create_table :repositories do |t|
      t.integer :host_id
      t.string :full_name
      t.string :default_branch, default: 'master'
      t.json :committers
      t.integer :total_commits
      t.integer :total_committers
      t.float :mean_commits
      t.float :dds
      t.datetime :last_synced_at
      t.string :last_synced_commit

      t.timestamps
    end
  end
end
