module HostRedirect
  extend ActiveSupport::Concern

  included do
    before_action :redirect_to_canonical_host, only: [:show]
  end

  private

  def find_host_with_redirect(host_name)
    # Try exact match first
    host = Host.find_by(name: host_name)
    return host if host

    # Try case-insensitive search
    host = Host.where('lower(name) = ?', host_name.downcase).first
    if host
      # If we found a host with different case, redirect to canonical version
      redirect_to_canonical_host_path(host)
      return nil
    end

    # Host not found
    raise ActiveRecord::RecordNotFound
  end

  def redirect_to_canonical_host
    return unless params[:id] || params[:host_id]
    
    host_param = params[:id] || params[:host_id]
    
    # Try exact match first
    host = Host.find_by(name: host_param)
    return if host

    # Try case-insensitive search
    host = Host.where('lower(name) = ?', host_param.downcase).first
    if host
      redirect_to_canonical_host_path(host)
      return
    end

    # Host not found, let the original action handle it
  end

  def redirect_to_canonical_host_path(host)
    # Determine if this is an API request
    is_api_request = request.path.start_with?('/api/')
    
    # Build the redirect path based on current route and controller
    if is_api_request
      redirect_path = build_api_redirect_path(host)
    else
      redirect_path = build_web_redirect_path(host)
    end
    
    redirect_to redirect_path, status: :moved_permanently
  end

  def build_api_redirect_path(host)
    case controller_name
    when 'hosts'
      api_v1_host_path(host.name)
    when 'repositories'
      case action_name
      when 'index'
        api_v1_host_repositories_path(host.name)
      when 'show', 'ping', 'sync_commits'
        api_v1_host_repository_path(host.name, params[:id])
      end
    when 'commits'
      api_v1_host_repository_commits_path(host.name, params[:repository_id])
    when 'committers'
      api_v1_host_committer_path(host.name, params[:id])
    else
      # Fallback for other controllers
      raise "Unknown API controller: #{controller_name}"
    end
  end

  def build_web_redirect_path(host)
    case controller_name
    when 'hosts'
      host_path(host.name)
    when 'repositories'
      case action_name
      when 'index'
        host_repositories_path(host.name)
      when 'show'
        host_repository_path(host.name, params[:id])
      end
    when 'committers'
      case action_name
      when 'index'
        host_committers_path(host.name)
      when 'show'
        host_committer_path(host.name, params[:id])
      end
    when 'owners'
      case action_name
      when 'index'
        host_owners_path(host.name)
      when 'show'
        host_owner_path(host.name, params[:id])
      end
    else
      # Fallback for other controllers
      raise "Unknown web controller: #{controller_name}"
    end
  end
end