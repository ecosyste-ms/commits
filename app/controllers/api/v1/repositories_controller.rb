class Api::V1::RepositoriesController < Api::V1::ApplicationController
  before_action :find_host, only: [:index, :show, :ping, :chart_data]
  skip_before_action :set_cache_headers, only: [:lookup, :ping]
  skip_before_action :set_api_cache_headers, only: [:lookup, :ping]

  def index
    scope = @host.repositories.visible.order('last_synced_at DESC').includes(:host)
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'last_synced_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('last_synced_at DESC')
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when @repositories, public: true
  end

  def lookup
    url = params[:url]

    host = nil
    path = nil

    if url.present? && url.start_with?('git@')
      # Handle SSH format like git@github.com:user/repo.git
      parts = url.split(':', 2)
      raise ActiveRecord::RecordNotFound unless parts.length == 2 && parts[1].present?

      user_host, repo_path = parts
      host = user_host.split('@').last
      path = repo_path.delete_suffix('.git').chomp('/')
    else
      begin
        parsed_url = Addressable::URI.parse(url)
        host = parsed_url.host
        path = parsed_url.path.delete_prefix('/').delete_suffix('.git').chomp('/')
      rescue
        raise ActiveRecord::RecordNotFound
      end
    end

    raise ActiveRecord::RecordNotFound unless host.present? && path.present?

    @host = Host.find_by_domain(host)
    raise ActiveRecord::RecordNotFound unless @host

    @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)

    if @repository
      raise ActiveRecord::RecordNotFound if @repository.owner_hidden?
      if @repository.last_synced_at.blank? || @repository.last_synced_at < 1.day.ago
        @repository.sync_async(request.remote_ip)
      end
      fresh_when @repository, public: true
      redirect_to api_v1_host_repository_path(@host, @repository)
    else
      @host.sync_repository_async(path, request.remote_ip)
      render json: { message: "Repository syncing started." }, status: :accepted
    end
  end

  def show
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    raise ActiveRecord::RecordNotFound if @repository.owner_hidden?
    fresh_when @repository, public: true

    # Load hidden committers for this repository in one query
    hidden_committer_list = @repository.committer_list.where(hidden: true)
    hidden_logins = Set.new(hidden_committer_list.map(&:login).compact)
    hidden_emails = Set.new(hidden_committer_list.flat_map(&:emails))

    # Filter committers
    @committers = (@repository.committers || []).reject do |c|
      hidden_logins.include?(c['login']) || hidden_emails.include?(c['email'])
    end

    @past_year_committers = (@repository.past_year_committers || []).reject do |c|
      hidden_logins.include?(c['login']) || hidden_emails.include?(c['email'])
    end
  end

  def ping
    @repository = Repository.find_or_create_from_host(@host, params[:id])
    raise ActiveRecord::RecordNotFound if @repository&.owner_hidden?

    # Skip if recently synced
    if @repository.last_synced_at.blank? || @repository.last_synced_at < 1.day.ago
      @repository.sync_async(request.remote_ip)
    end

    render json: { message: 'pong' }
  end

  def chart_data
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    raise ActiveRecord::RecordNotFound if @repository.owner_hidden?

    period = (params[:period].presence || 'month').to_sym
    scope = @repository.commits
    scope = scope.since(params[:start_date]) if params[:start_date].present?
    scope = scope.until(params[:end_date]) if params[:end_date].present?

    data = case params[:chart]
           when 'commits'
             scope.group_by_period(period, :timestamp).count
           when 'committers'
             scope.group_by_period(period, :timestamp).distinct.count(:author)
           when 'average_commits_per_committer'
             average_commits_per_committer(scope, period)
           else
             render json: { error: 'unknown chart' }, status: :bad_request
             return
           end

    fresh_when @repository, public: true
    render json: data
  end

  private

  def average_commits_per_committer(scope, period)
    commit_counts = scope.group_by_period(period, :timestamp).count
    committer_counts = scope.group_by_period(period, :timestamp).distinct.count(:author)

    commit_counts.each_with_object({}) do |(period_key, commit_count), averages|
      committer_count = committer_counts[period_key].to_i
      averages[period_key] = committer_count.zero? ? 0 : (commit_count.to_f / committer_count).round(2)
    end
  end

end
