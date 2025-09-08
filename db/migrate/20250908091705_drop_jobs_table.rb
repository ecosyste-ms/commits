class DropJobsTable < ActiveRecord::Migration[8.0]
  def change
    drop_table :jobs
  end
end
