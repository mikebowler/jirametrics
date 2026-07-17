# frozen_string_literal: true

# Walks a stream of BlockedStalledChange entries and totals up the value-add (active) time between
# issue_start and end_time. It's handed the already-computed stream and the resolved start/end so it
# never reaches back through the issue's collaborators.
#
# Returns [value_add_seconds, total_seconds].
class FlowEfficiencyCalculator
  def initialize blocked_stalled_changes:, issue_start:, end_time:
    @blocked_stalled_changes = blocked_stalled_changes
    @issue_start = issue_start
    @end_time = end_time
  end

  def calculate
    @active_start = nil
    @value_add_time = 0.0

    @blocked_stalled_changes.each_with_index do |change, index|
      break if change.time > @end_time

      process change, index
    end

    close_final_active_period

    [@value_add_time, @end_time - @issue_start]
  end

  def process change, index
    if index.zero?
      @active_start = change.time if change.active?
      return
    end

    process_transition change
  end

  def process_transition change
    # Already active and we just got another active.
    return if @active_start && change.active?

    if change.active?
      @active_start = change.time
    elsif @active_start && change.time >= @issue_start
      # Not active now but we have been. Record the active time.
      record_active_period ending_at: change.time
      @active_start = nil
    end
  end

  def record_active_period ending_at:
    @value_add_time += ending_at - [@issue_start, @active_start].max
  end

  def close_final_active_period
    return unless @active_start

    change_delta = @end_time - [@issue_start, @active_start].max
    @value_add_time += change_delta if change_delta.positive?
  end
end
