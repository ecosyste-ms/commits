class Api::V1::RepositoriesController < Api::V1::ApplicationController
  include HostRedirect

  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
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
      parts = url.split(':', 2)
      raise ActiveRecord::RecordNotFound unless parts.length == 2 && parts[1].present?
      
      user_host, repo_path = parts
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
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    fresh_when @repository, public: true
  end

  def ping
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
    @repository = Repository.find_or_create_from_host(@host, params[:id])
    
    # Skip if recently synced
    if @repository.last_synced_at.blank? || @repository.last_synced_at < 1.day.ago
      @repository.sync_async(request.remote_ip)
    end
    
    render json: { message: 'pong' }
  end

end