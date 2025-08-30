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
      result << render_issue(issue, child: false)
    end
    result
  end

  def atlassian_document_format
    @atlassian_document_format ||= AtlassianDocumentFormat.new(users: users, timezone_offset: timezone_offset)
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
    started_date = issue.board.cycletime.started_stopped_times(issue).first&.to_date
    return [] unless started_date

    blocked_stalled = issue.blocked_stalled_by_date(
      date_range: today..today, chart_end_time: time_range.end, settings: settings
    )[today]
    return [] if blocked_stalled.active?

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
    else
      lines << ["#{color_block '--stalled-color'} Stalled by inactivity: #{blocked_stalled.stalled_days} days"]
    end
    lines
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

    if done
      cycletime = issue.board.cycletime.cycletime(issue)

      line << "Cycletime: <b>#{label_days cycletime}</b>"
    else
      age = issue.board.cycletime.age(issue, today: date_range.end)
      line << "Age: <b>#{age ? label_days(age) : '(Not Started)'}</b>"
    end
    line << "Status: <b>#{format_status issue.status, board: issue.board}</b>"

    column = issue.board.visible_columns.find { |c| c.status_ids.include?(issue.status.id) }
    line << "Column: <b>#{column&.name || '(not visible on board)'}</b>"

    if issue.assigned_to
      line << "Assignee: <img src='#{issue.assigned_to_icon_url}' class='icon' /> <b>#{issue.assigned_to}</b>"
    end

    line << "Due: <b>#{issue.due_date}</b>" if issue.due_date

    block = lambda do |collection, label|
      unless collection.empty?
        text = collection.collect { |l| "<span class='label'>#{l}</span>" }.join(' ')
        line << "#{label} #{text}"
      end
    end
    block.call issue.labels, 'Labels:'
    block.call issue.component_names, 'Components:'

    [line]
  end

  def make_child_lines issue
    lines = []
    subtasks = issue.subtasks

    return lines if subtasks.empty?

    lines << '<section><div class="foldable">Child issues</div>'
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
      time = c.time.strftime '%b %d, %I:%M%P'

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
    result = []
    result << [atlassian_document_format.to_html(description)] if description
    result
  end

  def assemble_issue_lines issue, child:
    done = issue.done?

    lines = []
    lines << [make_title_line(issue: issue, done: done)]
    lines += make_parent_lines(issue) unless child
    lines += make_stats_lines(issue: issue, done: done)
    unless done
      lines += make_description_lines(issue)
      lines += make_sprints_lines(issue)
      lines += make_blocked_stalled_lines(issue)
      lines += make_child_lines(issue)
      lines += make_history_lines(issue)
    end
    lines
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
end
