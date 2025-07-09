class Api::V1::RepositoriesController < Api::V1::ApplicationController

  def index
    @host = Host.find_by_name!(params[:host_id])
    scope = @host.repositories.visible.order('last_synced_at DESC').includes(:host)
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'last_synced_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('last_synced_at DESC')
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when @repositories, public: true
  end

  def lookup
    url = params[:url]

    host = nil
    path = nil

    if url.present? && url.start_with?('git@')
      # Handle SSH format like git@github.com:user/repo.git
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
      redirect_to api_v1_host_repository_path(@host, @repository)
    else
      @host.sync_repository_async(path, request.remote_ip)
      render json: { message: "Repository syncing started." }, status: :accepted
    end
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    fresh_when @repository, public: true
  end

  def ping
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    if @repository
      @repository.sync_async
    else
      @host.sync_repository_async(path, request.remote_ip)
    end
    render json: { message: 'pong' }
  end

  def sync_commits
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    
    job_id = SyncCommitsWorker.perform_async(@repository.id)
    
    render json: { message: 'Sync commits job has been queued', job_id: job_id }, status: :accepted
  end
end