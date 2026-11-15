class OwnersController < ApplicationController
  before_action :find_host
  before_action :find_owner, only: [:show, :feed]

  def index
    scope = @host.owners.visible.where('repositories_count > 0').order(repositories_count: :desc, login: :asc)
    @pagy, @owners = pagy_countless(scope)
  end

  def show
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

  def feed
    @pagy, @repositories = pagy_countless(@host.repositories.owner(@owner).visible.order(last_synced_at: :desc))
    raise ActiveRecord::RecordNotFound if @repositories.empty?
    render 'repositories/feed' if stale?(etag: [@repositories, @repositories.map(&:last_synced_at)], public: true)
  end

  private

  def find_owner
    @owner = params[:id]
    owner_record = @host.owners.find_by(login: @owner.downcase)
    raise ActiveRecord::RecordNotFound if owner_record&.hidden?
  end
end
