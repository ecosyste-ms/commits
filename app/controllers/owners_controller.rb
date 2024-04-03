class OwnersController < ApplicationController
  def index
    # TODO
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @owner = params[:id]
    scope = @host.repositories.owner(@owner).visible

    sort = params[:sort].presence || 'last_synced_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
    raise ActiveRecord::RecordNotFound if @repositories.empty?
  end
end