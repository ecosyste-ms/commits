class HostsController < ApplicationController
  include HostRedirect

  def index
    @hosts = Host.all.visible.order('repositories_count DESC, commits_count DESC').limit(20)
    fresh_when @hosts, public: true
    @repositories = Repository.visible.order('last_synced_at DESC').includes(:host).limit(25)
  end

  def show
    @host = find_host_with_redirect(params[:id])
    return if performed?
    
    fresh_when @host, public: true
    scope = @host.repositories.visible

    sort = sanitize_sort(Repository.sortable_columns, default: 'last_synced_at')
    if params[:order] == 'asc'
      scope = scope.order(sort.asc.nulls_last)
    else
      scope = scope.order(sort.desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
  end
end