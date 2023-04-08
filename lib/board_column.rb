# frozen_string_literal: true

class BoardColumn
  attr_reader :status_ids, :min, :max, :raw
  attr_accessor :name

  def initialize raw
    @raw = raw
    @name = raw['name']
    @status_ids = raw['statuses'].collect { |status| status['id'].to_i }
    @min = raw['min']&.to_i
    @max = raw['max']&.to_i
  end
end
