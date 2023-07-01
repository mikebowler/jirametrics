# frozen_string_literal: true

require 'jirametrics/daily_wip_chart'

class DailyWipByAgeChart < DailyWipChart
  def default_header_text
    'Daily WIP grouped by Age'
  end

  def default_description_text
    <<-HTML
      <p>
        This chart shows the highest WIP on each given day. The WIP is color coded so you can see
        how old it is and hovering over the bar will show you exactly which work items it relates
        to. The green bar underneath, shows how many items completed on that day.
      </p>
      <p>
        "Completed without being started" reflects the fact that while we know that it completed
        that day, we were unable to determine when it had started. These items will show up in
        white at the top. Note that the white is approximate because we don't know exactly when
        it started so we're guessing.
      </p>
    HTML
  end

  def default_grouping_rules issue:, rules:
    cycletime = issue.board.cycletime
    started = cycletime.started_time(issue)&.to_date
    stopped = cycletime.stopped_time(issue)&.to_date

    rules.issue_hint = "(age: #{label_days (rules.current_date - started + 1).to_i})" if started

    if stopped && started.nil? # We can't tell when it started
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
      rules.color = '#66FF66'
      rules.group_priority = -1
    else
      rules.label = 'Start date unknown'
      rules.color = 'white'
      rules.group_priority = 11
      created_days = rules.current_date - created + 1
      rules.issue_hint = "(created: #{label_days created_days.to_i} earlier, stopped on #{stopped})"
    end
  end

  def stopped_today rules:
    rules.label = 'Completed'
    rules.color = '#009900'
    rules.group_priority = -2
  end

  def group_by_age started:, rules:
    age = rules.current_date - started + 1

    case age
    when 1
      rules.label = 'Less than a day'
      rules.color = '#aaaaaa'
      rules.group_priority = 10 # Highest is top
    when 2..7
      rules.label = 'A week or less'
      rules.color = '#80bfff'
      rules.group_priority = 9
    when 8..14
      rules.label = 'Two weeks or less'
      rules.color = '#ffd700'
      rules.group_priority = 8
    when 15..28
      rules.label = 'Four weeks or less'
      rules.color = '#ce6300'
      rules.group_priority = 7
    else
      rules.label = 'More than four weeks'
      rules.color = '#990000'
      rules.group_priority = 6
    end
  end
end
