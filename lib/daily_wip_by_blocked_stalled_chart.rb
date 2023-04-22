# frozen_string_literal: true

require './lib/daily_wip_chart'

class DailyWipByBlockedStalledChart < DailyWipChart
  def default_header_text
    'Daily WIP, grouped by Blocked and Stalled statuses'
  end

  def default_description_text
    <<-HTML
      <p>
        This chart highlights work that is blocked or stalled on each given day. In Jira terms, blocked
        means that the issue has been "flagged". Stalled indicates that the item hasn't had any updates in 5 days.
      </p>
      <p>
        Note that if an item tracks as both blocked and stalled, it will only show up in the flagged totals.
        It will not be double counted.
      </p>
      <p>
        The white section reflects items that have stopped but for which we can't identify the start date. As
        a result, we are unable to properly show the WIP for these items.
      </p>
    HTML
  end

  def key_blocked_stalled_change issue:, date:, end_time:
    stalled_change = nil
    blocked_change = nil

    issue.blocked_stalled_changes_on_date(date: date, end_time: end_time) do |change|
      blocked_change = change if change.blocked?
      stalled_change = change if change.stalled?
    end

    return blocked_change if blocked_change
    return stalled_change if stalled_change

    nil
  end

  def default_grouping_rules issue:, rules:
    started = issue.board.cycletime.started_time(issue)
    change = key_blocked_stalled_change issue: issue, date: rules.current_date, end_time: time_range.end

    if started.nil?
      rules.label = 'Start date unknown'
      rules.color = 'white'
      rules.group_priority = 4
      # rules.ignore
    elsif change&.blocked?
      rules.label = 'Blocked'
      rules.color = 'red'
      rules.group_priority = 1
      rules.issue_hint = "(#{change.reasons})"
    elsif change&.stalled?
      rules.label = 'Stalled'
      rules.color = 'orange'
      rules.group_priority = 2
      rules.issue_hint = "(Stalled #{label_days(change.stalled_days)})"
    else
      rules.label = 'Active'
      rules.color = 'lightgray'
      rules.group_priority = 3
    end
  end
end
