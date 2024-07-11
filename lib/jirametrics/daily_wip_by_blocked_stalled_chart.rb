# frozen_string_literal: true

require 'jirametrics/daily_wip_chart'

class DailyWipByBlockedStalledChart < DailyWipChart
  def default_header_text
    'Daily WIP, grouped by Blocked and Stalled statuses'
  end

  def default_description_text
    <<-HTML
      <div class="p">
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
      <div class="p">
        Note that if an item tracks as both blocked and stalled, it will only show up in the blocked totals.
        It will not be double counted.
      </div>
      <% if @has_completed_but_not_started %>
      <div class="p">
        #{color_block '--wip-chart-completed-but-not-started-color'} "Completed but not started"
        reflects the fact that while we know that it completed that day, we were unable to determine when
        it had started; it had moved directly from a To Do status to a Done status.
        The #{color_block '--body-background'} shading at the top shows when they might
        have been active. Note that the this grouping is approximate as we just don't know for sure.
      </div>
      <% end %>
      #{describe_non_working_days}
    HTML
  end

  def default_grouping_rules issue:, rules:
    started = issue.board.cycletime.started_time(issue)
    stopped_date = issue.board.cycletime.stopped_time(issue)&.to_date

    date = rules.current_date
    change = issue.blocked_stalled_by_date(date_range: date..date, chart_end_time: time_range.end)[date]

    stopped_today = stopped_date == rules.current_date

    if stopped_today && started.nil?
      @has_completed_but_not_started = true
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
