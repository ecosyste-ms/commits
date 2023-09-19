class AddBotStatsToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :total_bot_commits, :integer
    add_column :repositories, :total_bot_committers, :integer
    add_column :repositories, :past_year_total_bot_commits, :integer
    add_column :repositories, :past_year_total_bot_committers, :integer
  end
end
