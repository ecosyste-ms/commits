class HostsController < ApplicationController
  before_action :find_host_by_id, only: [:show]

  def index
    @hosts = Host.all.visible.order('repositories_count DESC, commits_count DESC').limit(20)
    @repositories = Repository.visible.order('last_synced_at DESC').includes(:host).limit(25)
    fresh_when @hosts, public: true
  end

  def show
    fresh_when @host, public: true
    scope = @host.repositories.visible

    sort = sanitize_sort(Repository.sortable_columns, default: 'last_synced_at')
    if params[:order] == 'asc'
      scope = scope.order(sort.asc.nulls_last)
    else
      scope = scope.order(sort.desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)

    respond_to do |format|
      format.html
      format.atom
    end
  end
end
