class RepositoriesController < ApplicationController
  def lookup
    url = params[:url]

    host = nil
    path = nil

    if url.start_with?('git@')
      user_host, repo_path = url.split(':', 2)
      host = user_host.split('@').last
      path = repo_path.delete_suffix('.git').chomp('/')
    else
      begin
        parsed_url = Addressable::URI.parse(url)
        host = parsed_url.host
        path = parsed_url.path.delete_prefix('/').delete_suffix('.git').chomp('/')
      rescue
        raise ActiveRecord::RecordNotFound
      end
    end

    raise ActiveRecord::RecordNotFound unless host.present? && path.present?

    @host = Host.find_by_domain(host)
    raise ActiveRecord::RecordNotFound unless @host

    @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)

    if @repository
      if @repository.last_synced_at.blank? || @repository.last_synced_at < 1.day.ago
        @repository.sync_async(request.remote_ip)
      end
      fresh_when @repository, public: true
      redirect_to host_repository_path(@host, @repository)
    else
      @host.sync_repository_async(path, request.remote_ip)
      raise ActiveRecord::RecordNotFound
    end
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    fresh_when @repository, public: true
    if @repository.nil?
      @job = @host.sync_repository_async(params[:id], request.remote_ip)
      @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
      raise ActiveRecord::RecordNotFound unless @repository
    end
  end

  def index
    @host = Host.find_by_name!(params[:host_id])
    redirect_to host_path(@host)
  end
end