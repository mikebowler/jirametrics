# frozen_string_literal: true

class FixVersion
  attr_reader :raw

  def initialize raw
    @raw = raw
  end

  def name
    @raw['name']
  end

  def description
    @raw['description']
  end

  def id
    @raw['id'].to_i
  end

  def release_date
    text = @raw['releaseDate']
    text.nil? ? nil : Date.parse(text)
  end

  def released?
    @raw['released']
  end

  def archived?
    @raw['archived']
  end
end
