class CommittersController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    scope = @host.committers.where('commits_count > 0')

    sort = params[:sort].presence || 'updated_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end

    @pagy, @committers = pagy_countless(scope)
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @committer = Committer.find_by_login(params[:id])
    if @committer.nil?
      @committer = Committer.email(params[:id]).first 
      if @committer && @committer.login.present?
        redirect_to host_committer_path(@host, @committer), status: :moved_permanently
      end
    end
    raise ActiveRecord::RecordNotFound unless @committer

    @pagy, @contributions = pagy_countless(@committer.contributions.includes(:repository).order('commit_count desc'))
  end
end