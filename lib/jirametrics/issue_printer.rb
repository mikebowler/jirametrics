# frozen_string_literal: true

class IssuePrinter
  def initialize issue
    @issue = issue
  end

  def to_s
    result = +''
    result << header_line
    result << assignee_line
    result << links_section
    result << history_section
    result
  end

  def header_line
    "#{@issue.key} (#{@issue.type}): #{@issue.compact_text @issue.summary, max: 200}\n"
  end

  def assignee_line
    assignee = @issue.raw['fields']['assignee']
    return '' if assignee.nil?

    "  [assignee] #{assignee['name'].inspect} <#{assignee['emailAddress']}>\n"
  end

  def links_section
    result = +''
    @issue.raw['fields']['issuelinks']&.each do |link|
      result << "  [link] #{link['type']['outward']} #{link['outwardIssue']['key']}\n" if link['outwardIssue']
      result << "  [link] #{link['type']['inward']} #{link['inwardIssue']['key']}\n" if link['inwardIssue']
    end
    result
  end

  def history_section
    result = +''
    result << cycletime_warning
    result << "  History:\n"
    result << render_history(build_history)
    result
  end

  def cycletime_warning
    return '' if @issue.board.cycletime

    "  Unable to determine start/end times as board #{@issue.board.id} has no cycletime specified\n"
  end

  # Each history entry is [time, type, detail, artificial?].
  def build_history
    start_stop_entries + discarded_change_entries + change_entries
  end

  def start_stop_entries
    return [] unless @issue.board.cycletime

    started_at, stopped_at = @issue.started_stopped_times
    entries = []
    entries << [started_at, nil, 'vvvv Started here vvvv', true] if started_at
    entries << [stopped_at, nil, '^^^^ Finished here ^^^^', true] if stopped_at
    entries
  end

  def discarded_change_entries
    (@issue.discarded_change_times || []).map do |time|
      [time, nil, '^^^^ Changes discarded ^^^^', true]
    end
  end

  def change_entries
    (@issue.changes + (@issue.discarded_changes || [])).map do |change|
      [change.time, change.field, create_change_message(change: change, issue: @issue), change.artificial?]
    end
  end

  def render_history history
    type_width = history.collect { |_time, type, _detail, _artificial| type&.length || 0 }.max
    sort_history!(history)
    history.map do |time, type, detail, _artificial|
      type = type.nil? ? '-' * type_width : type.rjust(type_width)
      "    #{time.strftime '%Y-%m-%d %H:%M:%S %z'} [#{type}] #{detail}\n"
    end.join
  end

  def create_change_message change:, issue:
    value, old_value = format_change_values(change: change, issue: issue)

    message = +''
    message << "#{old_value} -> " unless old_value.nil? || old_value.empty?
    message << value
    if change.artificial?
      message << ' (Artificial entry)'
    else
      message << " (Author: #{change.author})"
    end
    message
  end

  def format_change_values change:, issue:
    if change.status?
      value = "#{change.value.inspect}:#{change.value_id.inspect}"
      old_value = change.old_value ? "#{change.old_value.inspect}:#{change.old_value_id.inspect}" : nil
    elsif change.sprint?
      added = change.value_id - change.old_value_id
      removed = change.old_value_id - change.value_id
      value = "#{change.value.inspect} #{change.value_id}"
      value << " (added: #{added})" unless added.empty?
      value << " (removed: #{removed})" unless removed.empty?
      old_value = nil
    else
      value = issue.compact_text(change.value).inspect
      old_value = change.old_value ? issue.compact_text(change.old_value).inspect : nil
    end
    [value, old_value]
  end

  def sort_history! history
    history.sort! do |a, b|
      if a[0] == b[0]
        if a[1].nil?
          1
        elsif b[1].nil?
          -1
        else
          a[1] <=> b[1]
        end
      else
        a[0] <=> b[0]
      end
    end
  end
end
