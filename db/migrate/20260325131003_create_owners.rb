class CreateOwners < ActiveRecord::Migration[8.1]
  def change
    create_table :owners do |t|
      t.integer :host_id
      t.string :login
      t.boolean :hidden, default: false

      t.timestamps
    end

    add_index :owners, [:host_id, :login], unique: true
  end
end
