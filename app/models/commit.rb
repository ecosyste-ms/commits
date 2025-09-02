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
end
