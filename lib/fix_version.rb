# frozen_string_literal: true

class FixVersion
  attr_reader :raw

  def initialize raw
    @raw = raw
  end

  def name
    @raw['name']
  end

  def id
    @raw['id'].to_i
  end

  def released?
    @raw['released']
  end
end
