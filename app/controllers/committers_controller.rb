class CommittersController < ApplicationController
  include HostRedirect
  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
    scope = @host.committers.where('commits_count > 0')

    sort = sanitize_sort(Committer.sortable_columns)
    if params[:order] == 'asc'
      scope = scope.order(sort.asc.nulls_last)
    else
      scope = scope.order(sort.desc.nulls_last)
    end

    fresh_when scope, public: true
    @pagy, @committers = pagy_countless(scope)
  end

  def show
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
    @committer = @host.committers.find_by(login: params[:id])
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