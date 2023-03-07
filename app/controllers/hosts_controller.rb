class HostsController < ApplicationController
  def index
    @hosts = Host.all.where('repositories_count > 0 AND commits_count > 0').order('repositories_count DESC, commits_count DESC')

    @scope = Repository.where.not(last_synced_at: nil).where.not(total_commits: nil).order('last_synced_at DESC').includes(:host)
    @pagy, @repositories = pagy_countless(@scope, items: 10)
  end

  def show
    @host = Host.find_by_name!(params[:id])

    scope = @host.repositories.where.not(last_synced_at:nil)

    sort = params[:sort].presence || 'updated_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
  end
end