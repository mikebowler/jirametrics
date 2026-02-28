# frozen_string_literal: true

require 'jirametrics/value_equality'

class BlockedStalledChange
  include ValueEquality
  attr_reader :time, :blocking_issue_keys, :flag, :flag_reason, :status, :stalled_days, :status_is_blocking

  def initialize time:, flagged: nil, flag_reason: nil, status: nil, status_is_blocking: true,
    blocking_issue_keys: nil, stalled_days: nil
    @flag = flagged
    @flag_reason = flag_reason
    @status = status
    @status_is_blocking = status_is_blocking
    @blocking_issue_keys = blocking_issue_keys
    @stalled_days = stalled_days
    @time = time
  end

  def blocked? = !!(@flag || blocked_by_status? || @blocking_issue_keys)
  def stalled? = !!(@stalled_days || stalled_by_status?)
  def active? = !blocked? && !stalled?

  def blocked_by_status? = !!(@status && @status_is_blocking)
  def stalled_by_status? = !!(@status && !@status_is_blocking)

  def reasons
    result = []
    if blocked?
      result << (@flag_reason ? "Blocked by flag: #{@flag_reason}" : 'Blocked by flag') if @flag
      result << "Blocked by status: #{@status}" if blocked_by_status?
      result << "Blocked by issues: #{@blocking_issue_keys.join(', ')}" if @blocking_issue_keys
    elsif stalled_by_status?
      result << "Stalled by status: #{@status}"
    elsif @stalled_days
      result << "Stalled by inactivity: #{@stalled_days} days"
    end
    result.join(', ')
  end

  def as_symbol
    if blocked?
      :blocked
    elsif stalled?
      :stalled
    else
      :active
    end
  end

  def inspect
    text = "BlockedStalledChange(time: '#{@time}', "
    if active?
      text << 'Active'
    else
      text << reasons
    end
    text << ')'
  end
end
