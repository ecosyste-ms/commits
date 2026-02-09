class OwnersController < ApplicationController
  include HostRedirect
  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
    scope = @host.repositories.visible.group(:owner).count.sort_by { |k, v| [-v, k] }
    @pagy, @owners = pagy_array(scope)
  end

  def show
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
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