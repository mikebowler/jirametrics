# frozen_string_literal: true

require 'jirametrics/daily_wip_chart'

class DailyWipByAgeChart < DailyWipChart
  def initialize block
    super(block)

    add_trend_line line_color: '--aging-work-in-progress-by-age-trend-line-color', group_labels: [
      'Less than a day',
      'A week or less',
      'Two weeks or less',
      'Four weeks or less',
      'More than four weeks'
    ]
  end

  def default_header_text
    'Daily WIP grouped by Age'
  end

  def default_description_text
    <<-HTML
      <div class="p">
        This chart shows the highest WIP on each given day. The WIP is color coded so you can see
        how old it is and hovering over the bar will show you exactly which work items it relates
        to. The #{color_block '--wip-chart-completed-color'}
        #{color_block '--wip-chart-completed-but-not-started-color'}
        bars underneath, show how many items completed on that day.
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
      <div class="p">
        The #{color_block '--aging-work-in-progress-by-age-trend-line-color'} dashed line is a general trend line.
        <% if @has_completed_but_not_started %>
        Note that this trend line only includes items where we know both the start and end times of
        the work so it may not be as accurate as we hope.
        <% end %>
      </div>
    HTML
  end

  def default_grouping_rules issue:, rules:
    cycletime = issue.board.cycletime
    started = cycletime.started_time(issue)&.to_date
    stopped = cycletime.stopped_time(issue)&.to_date

    rules.issue_hint = "(age: #{label_days (rules.current_date - started + 1).to_i})" if started

    if stopped && started.nil? # We can't tell when it started
      @has_completed_but_not_started = true
      not_started stopped: stopped, rules: rules, created: issue.created.to_date
    elsif stopped == rules.current_date
      stopped_today rules: rules
    else
      group_by_age started: started, rules: rules
    end
  end

  def not_started stopped:, rules:, created:
    if stopped == rules.current_date
      rules.label = 'Completed but not started'
      rules.color = '--wip-chart-completed-but-not-started-color'
      rules.group_priority = -1
    else
      rules.label = 'Start date unknown'
      rules.color = '--body-background'
      rules.group_priority = 11
      created_days = rules.current_date - created + 1
      rules.issue_hint = "(created: #{label_days created_days.to_i} earlier, stopped on #{stopped})"
    end
  end

  def stopped_today rules:
    rules.label = 'Completed'
    rules.color = '--wip-chart-completed-color'
    rules.group_priority = -2
  end

  def group_by_age started:, rules:
    age = rules.current_date - started + 1

    case age
    when 1
      rules.label = 'Less than a day'
      rules.color = '--wip-chart-duration-less-than-day-color'
      rules.group_priority = 10 # Highest is top
    when 2..7
      rules.label = 'A week or less'
      rules.color = '--wip-chart-duration-week-or-less-color'
      rules.group_priority = 9
    when 8..14
      rules.label = 'Two weeks or less'
      rules.color = '--wip-chart-duration-two-weeks-or-less-color'
      rules.group_priority = 8
    when 15..28
      rules.label = 'Four weeks or less'
      rules.color = '--wip-chart-duration-four-weeks-or-less-color'
      rules.group_priority = 7
    else
      rules.label = 'More than four weeks'
      rules.color = '--wip-chart-duration-more-than-four-weeks-color'
      rules.group_priority = 6
    end
  end
end
