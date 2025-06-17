# frozen_string_literal: true

class DailyView < ChartBase
  attr_accessor :possible_statuses

  def initialize block
    super()

    header_text 'Daily View'
    description_text <<-HTML
      <div class="p">
        This view shows all the items you'll want to discuss during your daily coordination meeting
        (aka daily scrum, standup), in the order that you should be discussing them. The most important
        items are at the top, and the least at the bottom.
      </div>
      <div class="p">
        By default, we sort by priority first and then by age within each of those priorities.
      </div>
    HTML

    # init_configuration_block block do
    #   grouping_rules do |issue, rule|
    #     rule.label = issue.type
    #     rule.color = color_for type: issue.type
    #   end
    # end
  end

  def run
    aging_issues = issues.select do |issue|
      started_at, stopped_at = issue.board.cycletime.started_stopped_times(issue)
      started_at && !stopped_at
    end

    return "<h1>#{@header_text}</h1>There are no items currently in progress" if aging_issues.empty?

    result = +''
    result << render_top_text(binding)
    aging_issues.each do |issue|
      result << render_issue(issue)
    end
    result
    # wrap_and_render(binding, __FILE__)
  end

  def make_blocked_stalled_header issue
    today = date_range.end

    blocked_stalled = issue.blocked_stalled_by_date(
      date_range: today..today, chart_end_time: time_range.end, settings: settings
    )[today]

    result = []
    if blocked_stalled.blocked?
      marker = color_block '--blocked-color'
      result << ["#{marker} Blocked by flag"] if blocked_stalled.flag
      result << ["#{marker} Blocked by status: #{blocked_stalled.status}"] if blocked_stalled.blocked_by_status?
      blocked_stalled.blocking_issue_keys&.each do |key|
        result << ["#{marker} Blocked by issue: #{key}"]
        blocking_issue = issues.find { |i| i.key == key }
        result << blocking_issue if blocking_issue
      end
    elsif blocked_stalled.stalled_by_status?
      result << ["#{color_block '--stalled-color'} Stalled by status: #{blocked_stalled.status}"]
    elsif blocked_stalled.stalled_days
      result << ["#{color_block '--stalled-color'} Stalled by inactivity: #{blocked_stalled.stalled_days} days"]
    end
    result
  end

  def make_issue_header issue
    rows = []
    chunks = []
    chunks << "<b><a href='#{issue.url}'>#{issue.key}</a></b> #{issue.summary}"
    rows << chunks

    chunks = []
    chunks << "<img src='#{issue.type_icon_url}' /> <b>#{issue.type}</b>"

    chunks << "<img src='#{issue.priority_url}' /> <b>#{issue.priority_name}</b>"

    age = issue.board.cycletime.age(issue, today: date_range.end)
    chunks << "Age: <b>#{label_days age}</b>" if age

    chunks << "Status: <b>#{issue.status.name}</b>"

    column = issue.board.visible_columns.find { |c| c.status_ids.include?(issue.status.id) }
    chunks << "Column: <b>#{column&.name || '(not visible on board)'}</b>"

    if issue.assigned_to
      chunks << "Who: <img src='#{issue.assigned_to_icon_url}' width=16 height=16 /> <b>#{issue.assigned_to}</b>"
    end

    chunks << "Due: <b>#{issue.due_date}</b>" if issue.due_date

    rows << chunks

    blocked_stalled_header = make_blocked_stalled_header(issue)
    rows += blocked_stalled_header unless blocked_stalled_header.empty?

    rows
  end

  def render_issue issue, css_class: 'daily_issue'
    result = +''
    result << "<div class='#{css_class}'>"
    make_issue_header(issue).each do |row|
      if row.is_a? Issue
        result << render_issue(row, css_class: 'child_issue')
      else
        result << '<div class="heading">'
        row.each do |chunk|
          result << "<div>#{chunk}</div>"
        end
        result << '</div>'
      end
    end
    result << '</div>'
  end
end
