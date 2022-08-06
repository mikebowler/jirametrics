# frozen_string_literal: true

class FixVersion
  def initialize raw
    @raw = raw
  end

  def name
    @raw['name']
  end

  def released?
    @raw['released']
  end
end
