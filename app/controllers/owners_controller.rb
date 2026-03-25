class OwnersController < ApplicationController
  before_action :find_host

  def index
    scope = @host.repositories.visible.group(:owner).count.sort_by { |k, v| [-v, k.to_s] }
    @hidden_owners = @host.owners.hidden.pluck(:login).to_set
    @pagy, @owners = pagy_array(scope)
    @owners ||= []
  end

  def show
    @owner = params[:id]
    owner_record = @host.owners.find_by(login: @owner.downcase)
    raise ActiveRecord::RecordNotFound if owner_record&.hidden?
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
