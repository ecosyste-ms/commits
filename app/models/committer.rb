class Committer < ApplicationRecord
  belongs_to :host
  scope :email, ->(email) { where("emails @> ARRAY[?]::varchar[]", email) }

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

  def repositories
    if login.present?
      host.repositories.committer_login_or_email(login, emails.first)
    else
      host.repositories.committer_email(emails.first)
    end
  end
end
