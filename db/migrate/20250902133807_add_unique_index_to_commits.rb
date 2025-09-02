class AddUniqueIndexToCommits < ActiveRecord::Migration[8.0]
  def up
    # Add a unique index with a different name first
    add_index :commits, [:repository_id, :sha], unique: true, name: 'index_commits_on_repository_id_and_sha_unique'
    
    # Remove the existing non-unique index
    remove_index :commits, name: 'index_commits_on_repository_id_and_sha', if_exists: true
  end
  
  def down
    # Add back the non-unique index
    add_index :commits, [:repository_id, :sha], name: 'index_commits_on_repository_id_and_sha', if_not_exists: true
    
    # Remove the unique index
    remove_index :commits, name: 'index_commits_on_repository_id_and_sha_unique', if_exists: true
  end
end
