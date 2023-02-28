class RepositoriesController < ApplicationController
  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
  end

  def index
    @scope = Repository.where.not(last_synced_at: nil).where.not(total_commits: nil).order('last_synced_at DESC')
    @pagy, @repositories = pagy(@scope)
  end
end