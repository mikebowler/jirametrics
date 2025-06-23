# frozen_string_literal: true

class DailyView < ChartBase
  attr_accessor :possible_statuses

  def initialize _block
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
        Hover over the issue to make it stand out more.
      </div>
    HTML
  end

  def run
    aging_issues = select_aging_issues

    return "<h1>#{@header_text}</h1>There are no items currently in progress" if aging_issues.empty?

    result = +''
    result << render_top_text(binding)
    aging_issues.each do |issue|
      result << render_issue(issue)
    end
    result
  end

  def select_aging_issues
    aging_issues = issues.select do |issue|
      started_at, stopped_at = issue.board.cycletime.started_stopped_times(issue)
      started_at && !stopped_at
    end

    today = date_range.end
    aging_issues.collect do |issue|
      [issue, issue.priority_name, issue.board.cycletime.age(issue, today: today)]
    end.sort(&issue_sorter).collect(&:first)
  end

  def issue_sorter
    priority_names = settings['priority_order']
    lambda do |a, b|
      a_issue, a_priority, a_age = *a
      b_issue, b_priority, b_age = *b

      a_priority_index = priority_names.index(a_priority)
      b_priority_index = priority_names.index(b_priority)

      if a_priority_index.nil? && b_priority_index.nil?
        result = a_priority <=> b_priority
      elsif a_priority_index.nil?
        result = 1
      elsif b_priority_index.nil?
        result = -1
      else
        result = b_priority_index <=> a_priority_index
      end

      result = b_age <=> a_age if result.zero?
      result = a_issue <=> b_issue if result.zero?
      result
    end
  end

  def make_blocked_stalled_lines issue
    today = date_range.end

    blocked_stalled = issue.blocked_stalled_by_date(
      date_range: today..today, chart_end_time: time_range.end, settings: settings
    )[today]

    lines = []
    if blocked_stalled.blocked?
      marker = color_block '--blocked-color'
      lines << ["#{marker} Blocked by flag"] if blocked_stalled.flag
      lines << ["#{marker} Blocked by status: #{blocked_stalled.status}"] if blocked_stalled.blocked_by_status?
      blocked_stalled.blocking_issue_keys&.each do |key|
        lines << ["#{marker} Blocked by issue: #{key}"]
        blocking_issue = issues.find { |i| i.key == key }
        lines << blocking_issue if blocking_issue
      end
    elsif blocked_stalled.stalled_by_status?
      lines << ["#{color_block '--stalled-color'} Stalled by status: #{blocked_stalled.status}"]
    elsif blocked_stalled.stalled_days
      lines << ["#{color_block '--stalled-color'} Stalled by inactivity: #{blocked_stalled.stalled_days} days"]
    end
    lines
  end

  def make_stats_lines issue
    lines = []

    title_line = +''
    title_line << color_block('--expedited-color', title: 'Expedited') if issue.expedited?
    title_line << "<img src='#{issue.type_icon_url}' title='#{issue.type}' /> "
    title_line << "<b><a href='#{issue.url}'>#{issue.key}</a></b> <i>#{issue.summary}</i>"
    lines << [title_line]

    chunks = []

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
    lines << chunks

    lines
  end

  def make_child_lines issue
    lines = []
    subtasks = issue.subtasks.reject { |i| i.done? }

    unless subtasks.empty?
      icon_urls = subtasks.collect(&:type_icon_url).uniq.collect { |url| "<img src='#{url}' />" }
      lines << (icon_urls << 'Incomplete child issues')
      lines += subtasks
    end
    lines
  end

  def jira_rich_text_to_html text
    text.gsub(/{color:(#\w{6})}([^{]+){color}/, '<span style="color: \1">\2</span>')
  end

  def make_comment_lines issue
    comments = issue.changes.select { |i| i.comment? }.reverse
    lines = []
    return lines if comments.empty?

    lines << ['Comments']
    comments.each do |c|
      text = jira_rich_text_to_html c.value
      time = c.time.strftime '%Y-%b-%d %I:%M%P'
      lines << [
        "<span class='comment'>#{time} " \
        "<img src='#{c.author_icon_url}' width=16 height=16 /> " \
        "#{c.author} &rarr; #{text}</span>"
      ]
    end
    lines
  end

  def assemble_issue_lines issue
    lines = []
    lines += make_stats_lines(issue)
    lines += make_blocked_stalled_lines(issue)
    lines += make_child_lines(issue)
    lines += make_comment_lines(issue)
    lines
  end

  def render_issue issue, css_class: 'daily_issue'
    result = +''
    result << "<div class='#{css_class}'>"
    assemble_issue_lines(issue).each do |row|
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
