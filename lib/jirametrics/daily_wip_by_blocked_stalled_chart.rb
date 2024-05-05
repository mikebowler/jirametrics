# frozen_string_literal: true

require 'jirametrics/daily_wip_chart'

class DailyWipByBlockedStalledChart < DailyWipChart
  def default_header_text
    'Daily WIP, grouped by Blocked and Stalled statuses'
  end

  def default_description_text
    <<-HTML
      <div>
        This chart highlights work that is #{color_block '--blocked-color'} blocked, 
        #{color_block '--stalled-color'} stalled, or
        #{color_block '--wip-chart-active-color'} active on each given day.
        <ul>
          <li>#{color_block '--blocked-color'} Blocked could mean that the item has been flagged or it's
            in a status that is configured as blocked, or it could have a link showing that it is blocked
          by another item. It all depends how the report has been configured.</li>
          <li>#{color_block '--stalled-color'} Stalled indicates that there has been no activity on this
          item in five days.</li>
        </ul>
      </div>
      <p>
        Note that if an item tracks as both blocked and stalled, it will only show up in the blocked totals.
        It will not be double counted.
      </p>
      <div>
        The #{color_block '--body-background'} shaded section reflects items that have stopped but for which we can't identify the start date. As
        a result, we are unable to properly show the WIP for these items.
      </div>
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
    stopped_date = issue.board.cycletime.stopped_time(issue)&.to_date
    change = key_blocked_stalled_change issue: issue, date: rules.current_date, end_time: time_range.end

    stopped_today = stopped_date == rules.current_date

    if stopped_today && started.nil?
      rules.label = 'Completed but not started'
      rules.color = '--wip-chart-completed-but-not-started-color'
      rules.group_priority = -1
    elsif stopped_today
      rules.label = 'Completed'
      rules.color = '--wip-chart-completed-color'
      rules.group_priority = -2
    elsif started.nil?
      rules.label = 'Start date unknown'
      rules.color = '--body-background'
      rules.group_priority = 4
    elsif change&.blocked?
      rules.label = 'Blocked'
      rules.color = '--blocked-color'
      rules.group_priority = 1
      rules.issue_hint = "(#{change.reasons})"
    elsif change&.stalled?
      rules.label = 'Stalled'
      rules.color = '--stalled-color'
      rules.group_priority = 2
      rules.issue_hint = "(#{change.reasons})"
    else
      rules.label = 'Active'
      rules.color = '--wip-chart-active-color'
      rules.group_priority = 3
    end
  end
end
