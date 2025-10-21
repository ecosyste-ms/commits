class AddHiddenToCommitters < ActiveRecord::Migration[8.0]
  def change
    add_column :committers, :hidden, :boolean, default: false, null: false
  end
end
