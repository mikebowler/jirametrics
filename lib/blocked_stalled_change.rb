# frozen_string_literal: true

class BlockedStalledChange
  attr_reader :time, :blocking_issue_keys, :flag, :blocking_status, :stalled_days

  def initialize time:, flagged: nil, blocking_status: nil, status_is_blocking: true, blocking_issue_keys: nil, stalled_days: nil
    @flag = flagged
    @blocking_status = blocking_status
    @status_is_blocking = status_is_blocking
    @blocking_issue_keys = blocking_issue_keys
    @stalled_days = stalled_days
    @time = time
  end

  def blocked? = @flag || blocked_by_status? || @blocking_issue_keys
  def stalled? = @stalled_days || stalled_by_status?
  def active? = !blocked? && !stalled?

  def blocked_by_status? = (@blocking_status && @status_is_blocking)
  def stalled_by_status? = (@blocking_status && !@status_is_blocking)

  def ==(other)
    (other.class == self.class) && (other.state == state)
  end

  def state
    instance_variables.map { |variable| instance_variable_get variable }
  end

  def reasons
    result = []
    if blocked?
      result << 'Blocked by flag' if @flag
      result << "Blocked by status: #{@blocking_status}" if @blocking_status
      result << "Blocked by issues: #{@blocking_issue_keys.join(', ')}" if @blocking_issue_keys
    elsif stalled_by_status?
      result << "Stalled by status: #{@blocking_status}"
    elsif @stalled_days
      result << "Stalled by inactivity: #{@stalled_days} days"
    end
    result.join(', ')
  end
end
