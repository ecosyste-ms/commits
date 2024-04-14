class CommittersController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    scope = @host.committers
    @pagy, @committers = pagy(scope)
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @committer = Committer.find_by_login(params[:id])
    if @committer.nil?
      @committer = Committer.email(params[:id]).first 
      if @committer.login.present?
        redirect_to host_committer_path(@host, @committer), status: :moved_permanently
      end
    end
    raise ActiveRecord::RecordNotFound unless @committer
    @pagy, @repositories = pagy(@committer.repositories)
  end
end