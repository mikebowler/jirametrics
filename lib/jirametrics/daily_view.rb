# frozen_string_literal: true

class DailyView < ChartBase
  attr_accessor :possible_statuses

  def initialize _block
    super()

    header_text 'Daily View'
    description_text <<-HTML
      <div class="p">
        This view shows all the items (<%= aging_issues.count %>) you'll want to discuss during your daily
        coordination meeting
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

    if aging_issues.empty?
      return "<h1 class='foldable'>#{@header_text}</h1><div>There are no items currently in progress</div>"
    end

    result = +''
    result << render_top_text(binding)
    aging_issues.each do |issue|
      result << render_issue(issue, child: false)
    end
    result
  end

  def select_aging_issues
    aging_issues = issues.select do |issue|
      started_at, stopped_at = issue.started_stopped_times
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
    started_date = issue.started_stopped_times.first&.to_date
    return [] unless started_date

    blocked_stalled = issue.blocked_stalled_by_date(
      date_range: today..today, chart_end_time: time_range.end, settings: settings
    )[today]
    return [] if blocked_stalled.active?

    if blocked_stalled.blocked?
      blocked_lines blocked_stalled
    elsif blocked_stalled.stalled_by_status?
      [["#{color_block '--stalled-color'} Stalled by status: #{blocked_stalled.status}"]]
    else
      [["#{color_block '--stalled-color'} Stalled by inactivity: #{blocked_stalled.stalled_days} days"]]
    end
  end

  def blocked_lines blocked_stalled
    marker = color_block '--blocked-color'
    lines = []
    lines << ["#{marker} Blocked by flag"] if blocked_stalled.flag
    lines << ["#{marker} Blocked by status: #{blocked_stalled.status}"] if blocked_stalled.blocked_by_status?
    blocked_stalled.blocking_issue_keys&.each do |key|
      lines.concat blocking_issue_lines(key, marker)
    end
    lines
  end

  # The lines for one blocking issue: a foldable section embedding the issue when we have it, or a plain
  # "no description found" line when we only know its key.
  def blocking_issue_lines key, marker
    blocking_issue = issues.find_by_key key: key, include_hidden: true
    return [["#{marker} Blocked by issue: #{key} (no description found)"]] unless blocking_issue

    [
      "<section><div class=\"foldable startFolded\">#{marker} Blocked by issue: " \
        "#{make_issue_label issue: blocking_issue, done: blocking_issue.done?}</div>",
      blocking_issue,
      '</section>'
    ]
  end

  def make_issue_label issue:, done:
    label = "<img src='#{issue.type_icon_url}' title='#{issue.type}' class='icon' /> "
    label << '<s>' if done
    label << "<b><a href='#{issue.url}'>#{issue.key}</a></b> &nbsp;<i>#{issue.summary}</i>"
    label << '</s>' if done
    label
  end

  def make_title_line issue:, done:
    title_line = +''
    title_line << color_block('--expedited-color', title: 'Expedited') if issue.expedited?
    title_line << make_issue_label(issue: issue, done: done)
    title_line
  end

  def make_parent_lines issue
    lines = []
    parent_key = issue.parent_key
    if parent_key
      parent = issues.find_by_key key: parent_key, include_hidden: true
      text = parent ? make_issue_label(issue: parent, done: parent.done?) : parent_key
      lines << ["Parent: #{text}"]
    end
    lines
  end

  def make_stats_lines issue:, done:
    line = []
    line << "<img src='#{issue.priority_url}' class='icon' /> <b>#{issue.priority_name}</b>"
    line << progress_line(issue, done)
    line << "Status: <b>#{format_status issue.status, board: issue.board}</b>"

    column = issue.board.visible_columns.find { |c| c.status_ids.include?(issue.status.id) }
    line << "Column: <b>#{column&.name || '(not visible on board)'}</b>"

    if issue.assigned_to
      line << "Assignee: <img src='#{issue.assigned_to_icon_url}' class='icon' /> <b>#{issue.assigned_to}</b>"
    end

    due = due_date_line(issue)
    line << due if due
    line.concat label_lines(issue)

    [line]
  end

  # 'Cycletime: ...' for finished issues, otherwise 'Age: ...' (or '(Not Started)' when it hasn't started).
  def progress_line issue, done
    if done
      "Cycletime: <b>#{label_days issue.board.cycletime.cycletime(issue)}</b>"
    else
      age = issue.board.cycletime.age(issue, today: date_range.end)
      "Age: <b>#{age ? label_days(age) : '(Not Started)'}</b>"
    end
  end

  # 'Due: ...' with a relative 'today/in N days/N days ago' hint, highlighted when overdue. nil when
  # the issue has no due date.
  def due_date_line issue
    return nil unless issue.due_date

    days = (issue.due_date - date_range.end).to_i
    relative =
      if days.zero? then 'today'
      elsif days.positive? then "in #{label_days days}"
      else "#{label_days(-days)} ago"
      end
    content = "#{issue.due_date} (#{relative})"
    content = "<span style='background: var(--warning-banner)'>#{content}</span>" if days.negative?
    "Due: <b>#{content}</b>"
  end

  # One 'Labels: ...' and/or 'Components: ...' line, each listing its non-empty collection as label spans.
  def label_lines issue
    { 'Labels:' => issue.labels, 'Components:' => issue.component_names }.filter_map do |label, collection|
      next if collection.empty?

      spans = collection.collect { |item| "<span class='label'>#{item}</span>" }.join(' ')
      "#{label} #{spans}"
    end
  end

  def make_child_lines issue
    lines = []
    subtasks = issue.subtasks

    return lines if subtasks.empty?

    lines << "<section><div class=\"foldable startFolded\">Child issues (#{subtasks.count})</div>"
    lines += subtasks
    lines << '</section>'

    lines
  end

  def make_history_lines issue
    history = issue.changes.reverse
    lines = []

    lines << '<section><div class="foldable startFolded">Issue history</div>'
    table = +''
    table << '<table>'
    history.each do |c|
      time = c.time.strftime '%b %d, %Y @ %I:%M%P'

      table << '<tr>'
      table << "<td><span class='time' title='Timestamp: #{c.time}'>#{time}</span></td>"
      table << "<td><img src='#{c.author_icon_url}' class='icon' title='#{c.author}' /></td>"
      text = history_text change: c, board: issue.board
      table << "<td><span class='field'>#{c.field_as_human_readable}</span> #{text}</td>"
      table << '</tr>'
    end
    table << '</table>'
    lines << [table]
    lines << '</section>'
    lines
  end

  def history_text change:, board:
    convertor = ->(value, _id) { value.inspect }
    convertor = ->(_value, id) { format_status(board.possible_statuses.find_by_id(id), board: board) } if change.status?

    if change.comment? || change.description?
      atlassian_document_format.to_html(change.value)
    elsif %w[status priority assignee duedate issuetype].include?(change.field)
      to = convertor.call(change.value, change.value_id)
      if change.old_value
        from = convertor.call(change.old_value, change.old_value_id)
        "Changed from #{from} to #{to}"
      else
        "Set to #{to}"
      end
    elsif change.flagged?
      change.value == '' ? 'Off' : 'On'
    else
      change.value
    end
  end

  def make_sprints_lines issue
    return [] unless issue.board.scrum?

    sprint_names = issue.sprints.collect do |sprint|
      if sprint.closed?
        "<s>#{sprint.name}</s>"
      else
        sprint.name
      end
    end

    return [['Sprints: NONE']] if sprint_names.empty?

    [[+'Sprints: ' << sprint_names
      .collect { |name| "<span class='label'>#{name}</span>" }
      .join(' ')]]
  end

  def make_description_lines issue
    description = issue.raw['fields']['description']
    return [] unless description

    text = "<div class='foldable startFolded'>Description</div>" \
           "<div>#{atlassian_document_format.to_html(description)}</div>"
    [[text]]
  end

  def assemble_issue_lines issue, child:
    done = issue.done?

    lines = []
    lines << [make_title_line(issue: issue, done: done)]
    lines << make_not_visible_line(issue)
    lines += make_parent_lines(issue) unless child
    lines += make_stats_lines(issue: issue, done: done)
    unless done
      lines += make_description_lines(issue)
      lines += make_sprints_lines(issue)
      lines += make_blocked_stalled_lines(issue)
      lines += make_child_lines(issue)
      lines += make_history_lines(issue)
    end
    lines.compact
  end

  def render_issue issue, child:
    css_class = child ? 'child_issue' : 'daily_issue'
    result = +''
    result << "<div class='#{css_class}'>"
    assemble_issue_lines(issue, child: child).each do |row|
      if row.is_a? Issue
        result << render_issue(row, child: true)
      elsif row.is_a?(String)
        result << row
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

  def make_not_visible_line issue
    not_visible_text issue
  end
end
