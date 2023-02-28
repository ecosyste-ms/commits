class Repository < ApplicationRecord
  belongs_to :host

  validates :full_name, presence: true

  def to_s
    full_name
  end

  def to_param
    full_name
  end

  def subgroups
    return [] if full_name.split('/').size < 3
    full_name.split('/')[1..-2]
  end

  def project_slug
    full_name.split('/').last
  end

  def project_name
    full_name.split('/')[1..-1].join('/')
  end

  def owner
    full_name.split('/').first
  end

  def sync_details
    json = fetch_details
    return unless json

    self.default_branch = json['default_branch']
    self.save
  end

  def repos_url
    "https://repos.ecosyste.ms/api/v1/hosts/#{host.name}/repositories/#{full_name}"
  end

  def fetch_details
    conn = Faraday.new(repos_url) do |f|
      f.request :json
      f.request :retry
      f.response :json
    end
    response = conn.get
    return nil unless response.success?
    json = response.body
  end

  def folder_name
    full_name.split('/').last
  end

  def html_url
    "#{host.url}/#{full_name}"
  end

  def git_clone_url
    "#{host.url}/#{full_name}.git"
  end

  def fetch_head_sha
    `git ls-remote #{git_clone_url} #{default_branch}`.split("\t").first
  end

  # TODO support hg and svn repos

  def count_commits
    sync_details
    last_commit = fetch_head_sha

    if last_synced_commit == last_commit
      `rm -rf #{folder_name}`
      updates = {
        last_synced_at: Time.now
      }
    else
      `git clone -b #{default_branch} --single-branch #{git_clone_url}`
      last_commit = `git -C #{folder_name} rev-parse HEAD`.strip
      output = `git -C #{folder_name} shortlog -s -n -e --no-merges`
      committers = parse_commit_counts(output)
      `rm -rf #{folder_name}`

      total_commits = committers.sum{|h| h[:count]}

      updates = {
        committers: committers,
        last_synced_commit: last_commit,
        total_commits: total_commits,
        total_committers: committers.length,
        mean_commits: (total_commits.to_f / committers.length),
        dds: 1 - (committers.first[:count].to_f / total_commits),
        last_synced_at: Time.now
      }
    end

    update(updates)
  end

  def parse_commit_counts(output)
    # parse the output of the git command
    # return an array of hashes with the author and commit count
    output.split("\n").map do |line|
      count, author = line.split("\t")
      name, email = author.split("<")
      email.gsub!(/[<>]/, '')
      { name: name.strip, email: email, count: count.to_i }
    end
  end
end
