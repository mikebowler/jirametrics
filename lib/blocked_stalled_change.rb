# frozen_string_literal: true

class BlockedStalledChange
  attr_reader :action

  def initialize type:, time:, details: nil
    possible_types = %i[flagged blocked_status blocked_link stalled active]
    raise "Type was #{type.inspect}. Must be one of #{possible_types.inspect}" unless possible_types.include? type

    @type = type
    @details = details
    @time = time
  end

  def blocked? = %i[flagged blocked_status blocked_link].include(@type)
  def stalled? = @type == :stalled
  def active? = @type == :active

  def ==(other)
    (other.class == self.class) && (other.state == state)
  end

  def state
    instance_variables.map { |variable| instance_variable_get variable }
  end
end
