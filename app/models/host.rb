class Host < ApplicationRecord
  has_many :repositories

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validates :kind, presence: true

  def to_s
    name
  end

  def to_param
    name
  end

  def self.sync_all
    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
    end
    
    response = conn.get('/api/v1/hosts')
    return nil unless response.success?
    json = response.body

    json.each do |host|
      Host.find_or_create_by(name: host['name']).tap do |r|
        r.url = host['url']
        r.kind = host['kind']
        r.last_synced_at = Time.now
        r.save
      end
    end
  end
end
