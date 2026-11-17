class Owner < ApplicationRecord
  belongs_to :host

  validates :login, presence: true, uniqueness: { scope: :host_id }

  scope :hidden, -> { where(hidden: true) }
  scope :visible, -> {
    where(hidden: [false, nil])
      .where('NOT EXISTS (SELECT 1 FROM owners hidden_owners WHERE hidden_owners.host_id = owners.host_id AND lower(hidden_owners.login) = lower(owners.login) AND hidden_owners.hidden = TRUE)')
  }

  def to_s
    login
  end

  def to_param
    login
  end
end
