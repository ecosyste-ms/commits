class Api::V1::HostsController < Api::V1::ApplicationController
  include HostRedirect

  def index
    @hosts = Host.all.visible.order('repositories_count DESC, commits_count DESC')
    fresh_when @hosts, public: true
  end

  def show
    @host = find_host_with_redirect(params[:id])
    return if performed?
    
    fresh_when @host, public: true
  end
end