# frozen_string_literal: true

class EstimationConfiguration
  attr_reader :units, :display_name, :field_id

  def initialize raw:
    @units = :story_points
    @display_name = 'Story Points'

    # If there wasn't an estimation section they rely on all defaults
    return if raw.nil?

    if raw['type'] == 'field'
      @field_id = raw['field']['fieldId']
      @display_name = raw['field']['displayName']
      if @field_id == 'timeoriginalestimate'
        @units = :seconds
        @display_name = 'Original estimate'
      end
    elsif raw['type'] == 'issueCount'
      @display_name = 'Issue Count'
      @units = :issue_count
    end
  end
end
