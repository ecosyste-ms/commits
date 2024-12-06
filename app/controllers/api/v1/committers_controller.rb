class Api::V1::CommittersController < Api::V1::ApplicationController
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
    @pagy, @repositories = pagy_countless(@committer.repositories)
  end
end