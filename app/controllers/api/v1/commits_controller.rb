class Api::V1::CommitsController < Api::V1::ApplicationController
  before_action :find_host

  def index
    repository_parts = params[:repository_id].split('/', -1)
    raise ActiveRecord::RecordNotFound if repository_parts.size < 2 || repository_parts.any?(&:blank?)

    owner = repository_parts.first
    raise ActiveRecord::RecordNotFound if @host.owner_hidden?(owner)

    @repository = Repository.find_or_create_from_host(@host, params[:repository_id])
    raise ActiveRecord::RecordNotFound unless @repository

    if @repository.sync_pending?
      @repository.sync_async(request.remote_ip)
      return render_pending_repository(@repository)
    end

    scope = @repository.commits

    scope = scope.since(params[:since]) if params[:since].present?
    scope = scope.until(params[:until]) if params[:until].present?

    sort = sanitize_sort(Commit.sortable_columns, default: 'timestamp')
    if params[:order] == 'asc'
      scope = scope.order(sort.asc)
    else
      scope = scope.order(sort.desc)
    end

    @pagy, @commits = pagy_countless(scope)
    fresh_when @commits, public: true
  end
end
