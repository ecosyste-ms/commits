class Committer < ApplicationRecord
  scope :email, ->(email) { where("emails @> ARRAY[?]::varchar[]", email) }
end
