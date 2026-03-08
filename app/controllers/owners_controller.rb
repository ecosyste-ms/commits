class OwnersController < ApplicationController
  before_action :find_host

  def index
    return if performed?

    scope = @host.repositories.visible.group(:owner).count.sort_by { |k, v| [-v, k] }
    @pagy, @owners = pagy_array(scope)
  end

  def show
    return if performed?

    @owner = params[:id]
    scope = @host.repositories.owner(@owner).visible

    sort = sanitize_sort(Repository.sortable_columns, default: 'last_synced_at')
    if params[:order] == 'asc'
      scope = scope.order(sort.asc.nulls_last)
    else
      scope = scope.order(sort.desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when(@repositories)
    raise ActiveRecord::RecordNotFound if @repositories.empty?
  end
end
