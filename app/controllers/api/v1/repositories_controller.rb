class Api::V1::RepositoriesController < Api::V1::ApplicationController

  def lookup
    url = params[:url]
    parsed_url = Addressable::URI.parse(url)
    @host = Host.find_by_domain(parsed_url.host)
    raise ActiveRecord::RecordNotFound unless @host
    path = parsed_url.path.delete_prefix('/').chomp('/')
    @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)
    if @repository
      @repository.sync_async(request.remote_ip) unless @repository.last_synced_at.present? && @repository.last_synced_at > 1.day.ago
      redirect_to repository_path(@repository)
    else
      @host.sync_repository_async(path, request.remote_ip) if path.present?
      redirect_to repository_path(@repository)
      render json: { error: 'Repository not found' }, status: :not_found
    end
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
  end
end