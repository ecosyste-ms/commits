class Api::V1::CommittersController < Api::V1::ApplicationController
  include HostRedirect

  def show
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
    @committer = @host.committers.find_by(login: params[:id])
    if @committer.nil?
      @committer = Committer.email(params[:id]).first 
      if @committer && @committer.login.present?
        redirect_to api_v1_host_committer_path(@host, @committer), status: :moved_permanently
      end
    end
    raise ActiveRecord::RecordNotFound unless @committer
    @pagy, @repositories = pagy_countless(@committer.repositories)
  end
end