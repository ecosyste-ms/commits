class CommitsController < ApplicationController
  before_action :find_host

  def index
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    raise ActiveRecord::RecordNotFound if @host.owner_hidden?(@repository.owner)

    scope = @repository.commits

    scope = scope.since(params[:since]) if params[:since].present?
    scope = scope.until(params[:until]) if params[:until].present?

    sort = sanitize_sort(Commit.sortable_columns, default: 'timestamp')
    if params[:order] == 'asc'
      scope = scope.order(sort.asc)
    else
      scope = scope.order(sort.desc)
    end

    fresh_when scope, public: true
    @pagy, @commits = pagy_countless(scope)
  end
end
