class OwnersController < ApplicationController
  before_action :find_host

  def index
    hidden = @host.owners.hidden.pluck(:login)
    scope = @host.repositories.visible
      .where.not(owner: nil)
      .select('owner, COUNT(*) AS repositories_count')
      .group(:owner)
      .order(Arel.sql('COUNT(*) DESC, owner ASC'))
    scope = scope.where.not(owner: hidden) if hidden.any?
    @pagy, @owners = pagy_countless(scope)
  end

  def show
    @owner = params[:id]
    owner_record = @host.owners.find_by(login: @owner.downcase)
    raise ActiveRecord::RecordNotFound if owner_record&.hidden?
    scope = @host.repositories.owner(@owner).visible

    sort = sanitize_sort(Repository.sortable_columns, default: 'last_synced_at')
    if params[:order] == 'asc'
      scope = scope.order(sort.asc)
    else
      scope = scope.order(sort.desc)
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when(@repositories)
    raise ActiveRecord::RecordNotFound if @repositories.empty?
  end
end
