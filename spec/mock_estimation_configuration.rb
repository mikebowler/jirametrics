# frozen_string_literal: true

require 'json'

class MockEstimationConfiguration
  attr_reader :units, :display_name, :field_id

  def initialize units: :story_points, display_name: 'Story Points', field_id: nil
    @units = units
    @display_name = display_name
    @field_id = field_id
  end
end
