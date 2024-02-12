class Commit < ApplicationRecord
  belongs_to :repository
  has_one :host, through: :repository

  validates :sha, presence: true, uniqueness: { scope: :repository_id }

  scope :since, ->(date) { where('timestamp > ?', date) }
  scope :until, ->(date) { where('timestamp < ?', date) }

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
end
