class AddPastYearFieldsToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :past_year_committers, :json
    add_column :repositories, :past_year_total_commits, :integer
    add_column :repositories, :past_year_total_committers, :integer
    add_column :repositories, :past_year_mean_commits, :float
    add_column :repositories, :past_year_dds, :float
  end
end
