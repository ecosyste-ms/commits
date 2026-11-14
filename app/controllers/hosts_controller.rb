class HostsController < ApplicationController
  before_action :find_host_by_id, only: [:show]

  def index
    @hosts = top_hosts
    fresh_when @hosts, public: true
    @repositories = Repository.visible.order('last_synced_at DESC').includes(:host).limit(25)
  end

  def show
    fresh_when @host, public: true
    scope = @host.repositories.visible

    sort = sanitize_sort(Repository.sortable_columns, default: 'last_synced_at')
    if params[:order] == 'asc'
      scope = scope.order(sort.asc)
    else
      scope = scope.order(sort.desc)
    end

    @pagy, @repositories = pagy_countless(scope)
  end

  def feed
    @hosts = top_hosts
    fresh_when @hosts, public: true
  end

  private

  def top_hosts
    Host.all.visible.order('repositories_count DESC, commits_count DESC').limit(20)
  end
end
