class Commit < ApplicationRecord
  belongs_to :repository
  has_one :host, through: :repository

  validates :sha, presence: true, uniqueness: { scope: :repository_id }
end
