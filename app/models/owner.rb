class Owner < ApplicationRecord
  belongs_to :host

  validates :login, presence: true, uniqueness: { scope: :host_id }

  scope :hidden, -> { where(hidden: true) }
  scope :visible, -> { where(hidden: [false, nil]) }

  def to_s
    login
  end

  def to_param
    login
  end
end
