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

  def merge!(others)
    others = Array(others).reject { |o| o.id == id }
    return self if others.empty?

    transaction do
      self.emails = (emails.to_a + others.flat_map(&:emails).compact).uniq
      self.hidden = true if others.any?(&:hidden?)
      save!

      existing_by_repo = contributions.index_by(&:repository_id)
      Contribution.where(committer_id: others.map(&:id)).find_each do |c|
        existing = existing_by_repo[c.repository_id]
        if existing
          existing.update!(commit_count: existing.commit_count.to_i + c.commit_count.to_i)
          c.delete
        else
          c.update!(committer_id: id)
          existing_by_repo[c.repository_id] = c
        end
      end

      Committer.where(id: others.map(&:id)).delete_all
    end
    update_commits_count
    self
  end

  def self.duplicate_groups
    select(:host_id, :login).where.not(login: [nil, '']).group(:host_id, :login).having('count(*) > 1')
  end

  def self.dedupe
    merged = 0
    duplicate_groups.each do |g|
      rows = where(host_id: g.host_id, login: g.login).order(:id).to_a
      keeper = rows.shift
      keeper.merge!(rows)
      merged += rows.length
      puts "committers:dedupe merged #{merged} rows" if (merged % 500).zero?
    end
    merged
  end

  def self.backfill_emails_from_repositories(batch_size: 1000)
    seen = 0
    updated = 0
    Repository.where.not(committers: nil).select(:id, :host_id, :committers).find_in_batches(batch_size: batch_size) do |batch|
      pairs = Hash.new { |h, k| h[k] = [] }
      batch.each do |r|
        Array(r.committers).each do |entry|
          login = entry['login']
          email = entry['email']
          next if login.blank? || email.blank?
          pairs[[r.host_id, login]] << email
        end
      end
      pairs.each do |(host_id, login), emails|
        committer = find_or_initialize_by(host_id: host_id, login: login)
        before = committer.emails.to_a
        merged = (before + emails).uniq
        next if committer.persisted? && merged == before
        committer.emails = merged
        committer.save!
        updated += 1
      end
      seen += batch.size
      puts "committers:backfill_emails processed #{seen} repositories, #{updated} committers updated"
    end
    updated
  end
end
