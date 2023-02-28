class CreateHosts < ActiveRecord::Migration[7.0]
  def change
    create_table :hosts do |t|
      t.string :name
      t.string :url
      t.string :kind
      t.datetime :last_synced_at

      t.timestamps
    end
  end
end
