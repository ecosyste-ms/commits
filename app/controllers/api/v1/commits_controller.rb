class Api::V1::CommitsController < Api::V1::ApplicationController
  before_action :find_host

  def index
    owner = params[:repository_id].split('/').first
    raise ActiveRecord::RecordNotFound if @host.owner_hidden?(owner)

    @repository = Repository.find_or_create_from_host(@host, params[:repository_id])

    if @repository.sync_pending?
      @repository.sync_async(request.remote_ip)
      return render_pending_repository(@repository)
    end

    scope = @repository.commits.order('timestamp DESC')

    scope = scope.since(params[:since]) if params[:since].present?
    scope = scope.until(params[:until]) if params[:until].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'timestamp'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('timestamp DESC')
    end

    @pagy, @commits = pagy_countless(@repository.commits.order('timestamp DESC'))
    fresh_when @commits, public: true
  end
end
