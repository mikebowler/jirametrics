# frozen_string_literal: true

class BlockedStalledChange
  attr_reader :time, :blocking_issue_keys

  def initialize time:, flagged: nil, blocking_status: nil, blocking_issue_keys: nil, stalled_days: nil
    @flag = flagged
    @blocking_status = blocking_status
    @blocking_issue_keys = blocking_issue_keys
    @stalled_days = stalled_days
    @time = time
  end

  def blocked? = @flag || @blocking_status || @blocking_issue_keys
  def stalled? = @stalled_days
  def active? = !blocked? && !stalled?

  def ==(other)
    (other.class == self.class) && (other.state == state)
  end

  def state
    instance_variables.map { |variable| instance_variable_get variable }
  end

  def reasons
    result = []
    result << 'Flagged' if @flag
    result << "Blocked by status: #{@blocking_status}" if @blocking_status
    result << "Blocked by issues: #{@blocking_issue_keys.join(', ')}" if @blocking_issue_keys
    result.join(', ')
  end
end
