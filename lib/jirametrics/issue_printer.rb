# frozen_string_literal: true

class IssuePrinter
  def initialize issue
    @issue = issue
  end

  def to_s
    issue = @issue
    result = +''
    result << "#{issue.key} (#{issue.type}): #{issue.compact_text issue.summary, max: 200}\n"

    assignee = issue.raw['fields']['assignee']
    result << "  [assignee] #{assignee['name'].inspect} <#{assignee['emailAddress']}>\n" unless assignee.nil?

    issue.raw['fields']['issuelinks']&.each do |link|
      result << "  [link] #{link['type']['outward']} #{link['outwardIssue']['key']}\n" if link['outwardIssue']
      result << "  [link] #{link['type']['inward']} #{link['inwardIssue']['key']}\n" if link['inwardIssue']
    end

    history = [] # time, type, detail

    if issue.board.cycletime
      started_at, stopped_at = issue.board.cycletime.started_stopped_times(issue)
      history << [started_at, nil, 'vvvv Started here vvvv', true] if started_at
      history << [stopped_at, nil, '^^^^ Finished here ^^^^', true] if stopped_at
    else
      result << "  Unable to determine start/end times as board #{issue.board.id} has no cycletime specified\n"
    end

    issue.discarded_change_times&.each do |time|
      history << [time, nil, '^^^^ Changes discarded ^^^^', true]
    end

    (issue.changes + (issue.discarded_changes || [])).each do |change|
      if change.status?
        value = "#{change.value.inspect}:#{change.value_id.inspect}"
        old_value = change.old_value ? "#{change.old_value.inspect}:#{change.old_value_id.inspect}" : nil
      else
        value = issue.compact_text(change.value).inspect
        old_value = change.old_value ? issue.compact_text(change.old_value).inspect : nil
      end

      message = +''
      message << "#{old_value} -> " unless old_value.nil? || old_value.empty?
      message << value
      if change.artificial?
        message << ' (Artificial entry)'
      else
        message << " (Author: #{change.author})"
      end
      history << [change.time, change.field, message, change.artificial?]
    end

    result << "  History:\n"
    type_width = history.collect { |_time, type, _detail, _artificial| type&.length || 0 }.max
    sort_history!(history)
    history.each do |time, type, detail, _artificial|
      type = type.nil? ? '-' * type_width : type.rjust(type_width)
      result << "    #{time.strftime '%Y-%m-%d %H:%M:%S %z'} [#{type}] #{detail}\n"
    end

    result
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
