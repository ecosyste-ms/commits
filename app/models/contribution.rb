class Contribution < ApplicationRecord
  belongs_to :committer
  belongs_to :repository
end
