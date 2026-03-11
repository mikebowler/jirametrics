# frozen_string_literal: true

class BoardFeature
  def initialize raw:
    @raw = raw
  end

  def name = @raw['feature']
  def enabled? = (@raw['state'] == 'ENABLED')

  def self.from_raw features_json
    features_json['features']&.map { |f| new(raw: f) } || []
  end
end
