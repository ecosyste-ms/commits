class OwnersController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    scope = @host.repositories.visible.group(:owner).count.sort_by { |k, v| [-v, k] }
    @pagy, @owners = pagy_array(scope)
    expires_in 1.day, public: true
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
    fresh_when(@repositories)
    raise ActiveRecord::RecordNotFound if @repositories.empty?
  end
end