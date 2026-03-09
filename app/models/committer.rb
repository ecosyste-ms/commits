class Committer < ApplicationRecord
  def self.sortable_columns
    {
      'commits_count' => 'commits_count',
      'login' => 'login',
      'updated_at' => 'updated_at',
      'created_at' => 'created_at',
    }
  end

  belongs_to :host
  scope :email, ->(email) { where("emails @> ARRAY[?]::varchar[]", email) }
  scope :visible, -> { where(hidden: false) }

  has_many :contributions, dependent: :destroy
  has_many :repositories, through: :contributions

  def to_s
    login || emails.first
  end

  def to_param
    login || emails.first
  end

  def html_url
    return if login.blank?
    "#{host.url}/#{login}"
  end

  def repositories_count
    contributions.count
  end

  def update_commits_count
    update(commits_count: contributions.sum(:commit_count))
  end
end
