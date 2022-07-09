# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkTable < ChartBase
  attr_accessor :today

  def initialize expedited_priority_name
    @expedited_priority_name = expedited_priority_name
    @blocked_icon = '🛑'
    @expedited_icon = '🔥'
    @stalled_icon = '🟧'
    @stalled_threshold = 5
  end

  def run
    @today = date_range.end
    aging_issues = select_aging_issues

    expedited_but_not_started = @issues.select do |issue|
      @cycletime.started_time(issue).nil? && @cycletime.stopped_time(issue).nil? && expedited?(issue)
    end
    aging_issues += expedited_but_not_started.sort_by(&:created)

    render(binding, __FILE__)
  end

  def select_aging_issues
    aging_issues = @issues.select { |issue| @cycletime.started_time(issue) && @cycletime.stopped_time(issue).nil? }
    aging_issues.sort { |a, b| @cycletime.age(b, today: @today) <=> @cycletime.age(a, today: @today) }
  end

  def expedited? issue
    issue.raw['fields']['priority']['name'] == @expedited_priority_name
  end

  def icon_span title:, icon:
    "<span title='#{title}' style='font-size: 0.8em;'>#{icon}</span>"
  end

  def expedited_text issue
    if expedited?(issue)
      icon_span(title: "Expedited: Has a priority of &quot;#{@expedited_priority_name}&quot;", icon: @expedited_icon)
    end
  end

  def blocked_text issue
    if issue.blocked_on_date? @today
      icon_span title: 'Blocked: Has the flag set', icon: @blocked_icon
    elsif issue.stalled_on_date?(@today, @stalled_threshold) && @cycletime.started_time(issue)
      icon_span(
        title: "Stalled: Hasn&apos;t had any activity in #{@stalled_threshold} days and isn&apos;t explicitly marked as blocked",
        icon: @stalled_icon
      )
    end
  end
end
