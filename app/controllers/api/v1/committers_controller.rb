class Api::V1::CommittersController < Api::V1::ApplicationController
  before_action :find_host

  def show
    @committer = @host.committers.find_by(login: params[:id])
    if @committer.nil?
      @committer = Committer.email(params[:id]).first
      if @committer && @committer.login.present?
        redirect_to api_v1_host_committer_path(@host, @committer), status: :moved_permanently
      end
    end
    raise ActiveRecord::RecordNotFound unless @committer
    @pagy, @contributions = pagy_countless(@committer.contributions.includes(:repository).order('commit_count desc'))
  end
end
