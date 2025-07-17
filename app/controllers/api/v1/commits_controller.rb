class Api::V1::CommitsController < Api::V1::ApplicationController
  include HostRedirect

  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed?
    
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)

    scope = @repository.commits.order('timestamp DESC')

    scope = scope.since(params[:since]) if params[:since].present?
    scope = scope.until(params[:until]) if params[:until].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'timestamp'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('timestamp DESC')
    end

    @pagy, @commits = pagy_countless(@repository.commits.order('timestamp DESC'))
    fresh_when @commits, public: true
  end
end