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

  def default_grouping_rules issue:, rules:
    started = cycletime.started_time(issue)
    if started.nil?
      rules.label = 'Start date unknown'
      rules.color = 'white'
      rules.group_priority = 4
      # rules.ignore
    elsif issue.blocked_on_date?(rules.current_date)
      rules.label = 'Blocked'
      rules.color = 'red'
      rules.group_priority = 1
    elsif issue.stalled_on_date?(rules.current_date)
      rules.label = 'Stalled'
      rules.color = 'orange'
      rules.group_priority = 2
    else
      rules.label = 'Active'
      rules.color = 'lightgray'
      rules.group_priority = 3
    end
  end
end
