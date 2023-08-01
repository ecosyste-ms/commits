class CreateCommitters < ActiveRecord::Migration[7.0]
  def change
    create_table :committers do |t|
      t.integer :host_id, index: true
      t.string :emails, array: true
      t.string :login
      t.integer :commits_count, default: 0

      t.timestamps
    end

    add_index :committers, :emails, using: :gin
  end
end
