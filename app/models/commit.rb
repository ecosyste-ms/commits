class Commit < ApplicationRecord
  CHART_PERIODS = %w[day week month quarter year].freeze

  def self.sortable_columns
    {
      'timestamp' => 'timestamp',
      'sha' => 'sha',
      'author' => 'author',
      'committer' => 'committer',
    }
  end

  belongs_to :repository
  has_one :host, through: :repository

  validates :sha, presence: true, uniqueness: { scope: :repository_id }

  scope :since, ->(date) { where('timestamp > ?', date) }
  scope :until, ->(date) { where('timestamp < ?', date) }
  scope :with_co_author, -> { where.not(co_author_email: nil) }
  
  before_save :extract_co_author_email

  def self.chart_data(period)
    commits = group_by_period(period, :timestamp).count
    committers = group_by_period(period, :timestamp).distinct.count(:author)
    average_commits_per_committer = commits.to_h do |date, count|
      committer_count = committers[date].to_i
      [date, committer_count.positive? ? count.fdiv(committer_count).round(2) : 0]
    end

    {
      commits: commits,
      committers: committers,
      average_commits_per_committer: average_commits_per_committer
    }
  end

  def labelled_stats
    {
      files_changed: files_changed,
      additions: additions,
      deletions: deletions
    }
  end

  def files_changed
    stats[0]
  end

  def additions
    stats[1]
  end

  def deletions
    stats[2]
  end

  def html_url
    "#{repository.html_url}/commit/#{sha}"
  end

  def co_authors
    return [] if message.blank?
    
    message.scan(/Co-authored-by:\s*(.+?)\s*<(.+?)>/i).map do |name, email|
      {
        name: name.strip,
        email: email.strip
      }
    end
  end

  def signed_off_by
    return [] if message.blank?
    
    message.scan(/Signed-off-by:\s*(.+?)\s*<(.+?)>/i).map do |name, email|
      {
        name: name.strip,
        email: email.strip
      }
    end
  end
  
  def extract_co_author_email
    # Use the first co-author from the existing co_authors method
    first_co_author = co_authors.first
    if first_co_author
      self.co_author_email = first_co_author[:email].downcase
    end
  end
  
  def self.extract_co_author_from_message(message)
    return nil if message.blank?
    
    # Extract email from: Co-authored-by: Name <email@example.com>
    match = message.match(/Co-authored-by:\s*.*?<(.+?)>/i)
    match[1].strip.downcase if match
  end
end
