# frozen_string_literal: true

class DataQualityReport < ChartBase
  attr_reader :discarded_changes_data, :entries # Both for testing purposes only
  attr_accessor :board_id

  class Entry
    attr_reader :started, :stopped, :issue, :problems

    def initialize started:, stopped:, issue:
      @started = started
      @stopped = stopped
      @issue = issue
      @problems = []
    end

    def report problem_key: nil, detail: nil
      @problems << [problem_key, detail]
    end
  end

  def initialize discarded_changes_data
    super()

    @discarded_changes_data = discarded_changes_data

    header_text 'Data Quality Report'
    description_text <<-HTML
      <p>
        We have a tendency to assume that anything we see in a chart is 100% accurate, although that's
        not always true. To understand the accuracy of the chart, we have to understand how accurate the
        initial data was and also how much of the original data set was used in the chart. This section
        will hopefully give you enough information to make that decision.
      </p>
    HTML
  end

  def run
    initialize_entries

    @entries.each do |entry|
      board = entry.issue.board
      backlog_statuses = board.backlog_statuses

      scan_for_completed_issues_without_a_start_time entry: entry
      scan_for_status_change_after_done entry: entry
      scan_for_backwards_movement entry: entry, backlog_statuses: backlog_statuses
      scan_for_issues_not_created_in_a_backlog_status entry: entry, backlog_statuses: backlog_statuses
      scan_for_stopped_before_started entry: entry
      scan_for_issues_not_started_with_subtasks_that_have entry: entry
      scan_for_incomplete_subtasks_when_issue_done entry: entry
      scan_for_discarded_data entry: entry
      scan_for_items_blocked_on_closed_tickets entry: entry
    end

    scan_for_issues_on_multiple_boards entries: @entries

    entries_with_problems = entries_with_problems()
    return '' if entries_with_problems.empty?

    caller_binding = binding
    result = +''
    result << render_top_text(caller_binding)

    result << '<ul class="quality_report">'
    result << render_problem_type(:discarded_changes)
    result << render_problem_type(:completed_but_not_started)
    result << render_problem_type(:status_changes_after_done)
    result << render_problem_type(:backwards_through_status_categories)
    result << render_problem_type(:backwords_through_statuses)
    result << render_problem_type(:status_not_on_board)
    result << render_problem_type(:created_in_wrong_status)
    result << render_problem_type(:stopped_before_started)
    result << render_problem_type(:issue_not_started_but_subtasks_have)
    result << render_problem_type(:incomplete_subtasks_when_issue_done)
    result << render_problem_type(:issue_on_multiple_boards)
    result << render_problem_type(:items_blocked_on_closed_tickets)
    result << '</ul>'

    result
  end

  def problems_for key
    result = []
    @entries.each do |entry|
      entry.problems.each do |problem_key, detail|
        result << [entry.issue, detail, key] if problem_key == key
      end
    end
    result
  end

  def render_problem_type problem_key
    problems = problems_for problem_key
    return '' if problems.empty?

    <<-HTML
      <li>
        #{__send__ :"render_#{problem_key}", problems}
        #{collapsible_issues_panel problems}
      </li>
    HTML
  end

  # Return a format that's easier to assert against
  def testable_entries
    formatter = ->(time) { time&.strftime('%Y-%m-%d %H:%M:%S %z') || '' }
    @entries.collect do |entry|
      [
        formatter.call(entry.started),
        formatter.call(entry.stopped),
        entry.issue
      ]
    end
  end

  def entries_with_problems
    @entries.reject { |entry| entry.problems.empty? }
  end

  def initialize_entries
    @entries = @issues.filter_map do |issue|
      started, stopped = issue.board.cycletime.started_stopped_times(issue)
      next if stopped && stopped < time_range.begin
      next if started && started > time_range.end

      Entry.new started: started, stopped: stopped, issue: issue
    end

    @entries.sort! do |a, b|
      a.issue.key =~ /.+-(\d+)$/
      a_id = $1.to_i

      b.issue.key =~ /.+-(\d+)$/
      b_id = $1.to_i

      a_id <=> b_id
    end
  end

  def scan_for_completed_issues_without_a_start_time entry:
    return unless entry.stopped && entry.started.nil?

    status_names = entry.issue.status_changes.filter_map do |change|
      format_status change, board: entry.issue.board
    end

    entry.report(
      problem_key: :completed_but_not_started,
      detail: "Status changes: #{status_names.join ' → '}"
    )
  end

  def scan_for_status_change_after_done entry:
    return unless entry.stopped

    changes_after_done = entry.issue.changes.select do |change|
      change.status? && change.time >= entry.stopped
    end
    done_status = changes_after_done.shift

    return if changes_after_done.empty?

    board = entry.issue.board
    problem = "Completed on #{entry.stopped.to_date} with status #{format_status done_status, board: board}."
    changes_after_done.each do |change|
      problem << " Changed to #{format_status change, board: board} on #{change.time.to_date}."
    end
    entry.report(
      problem_key: :status_changes_after_done,
      detail: problem
    )
  end

  def scan_for_backwards_movement entry:, backlog_statuses:
    issue = entry.issue

    # Moving backwards through statuses is bad. Moving backwards through status categories is almost always worse.
    last_index = -1
    issue.changes.each do |change|
      next unless change.status?

      board = entry.issue.board
      index = entry.issue.board.visible_columns.find_index { |column| column.status_ids.include? change.value_id }
      if index.nil?
        # If it's a backlog status then ignore it. Not supposed to be visible.
        next if entry.issue.board.backlog_statuses.include?(board.possible_statuses.find_by_id(change.value_id))

        detail = "Status #{format_status change, board: board} is not on the board"
        if issue.board.possible_statuses.find_by_id(change.value_id).nil?
          detail = "Status #{format_status change, board: board} cannot be found at all. Was it deleted?"
        end

        # If it's been moved back to backlog then it's on a different report. Ignore it here.
        detail = nil if backlog_statuses.any? { |s| s.name == change.value }

        entry.report(problem_key: :status_not_on_board, detail: detail) unless detail.nil?
      elsif change.old_value.nil?
        # Do nothing
      elsif index < last_index
        new_category = board.possible_statuses.find_by_id(change.value_id).category.name
        old_category = board.possible_statuses.find_by_id(change.old_value_id).category.name

        if new_category == old_category
          entry.report(
            problem_key: :backwords_through_statuses,
            detail: "Moved from #{format_status change, use_old_status: true, board: board}" \
              " to #{format_status change, board: board}" \
              " on #{change.time.to_date}"
          )
        else
          entry.report(
            problem_key: :backwards_through_status_categories,
            detail: "Moved from #{format_status change, use_old_status: true, board: board}" \
              " to #{format_status change, board: board}" \
              " on #{change.time.to_date}," \
              " crossing from category #{format_status change, use_old_status: true, board: board, is_category: true}" \
              " to #{format_status change, board: board, is_category: true}."
          )
        end
      end
      last_index = index || -1
    end
  end

  def scan_for_issues_not_created_in_a_backlog_status entry:, backlog_statuses:
    creation_change = entry.issue.changes.find { |issue| issue.status? }

    return if backlog_statuses.any? { |status| status.id == creation_change.value_id }

    status_string = backlog_statuses.collect { |s| format_status s, board: entry.issue.board }.join(', ')
    entry.report(
      problem_key: :created_in_wrong_status,
      detail: "Created in #{format_status creation_change, board: entry.issue.board}, " \
        "which is not one of the backlog statuses for this board: #{status_string}"
    )
  end

  def scan_for_stopped_before_started entry:
    return unless entry.stopped && entry.started && entry.stopped < entry.started

    entry.report(
      problem_key: :stopped_before_started,
      detail: "The stopped time '#{entry.stopped}' is before the started time '#{entry.started}'"
    )
  end

  def scan_for_issues_not_started_with_subtasks_that_have entry:
    return if entry.started

    started_subtasks = []
    entry.issue.subtasks.each do |subtask|
      started_subtasks << subtask if subtask.board.cycletime.started_stopped_times(subtask).first
    end

    return if started_subtasks.empty?

    subtask_labels = started_subtasks.collect do |subtask|
      subtask_label(subtask)
    end
    entry.report(
      problem_key: :issue_not_started_but_subtasks_have,
      detail: subtask_labels.join('<br />')
    )
  end

  def scan_for_items_blocked_on_closed_tickets entry:
    entry.issue.issue_links.each do |link|
      next unless settings['blocked_link_text'].include?(link.label)

      this_active = !entry.stopped
      other_active = !link.other_issue.board.cycletime.started_stopped_times(link.other_issue).last
      next unless this_active && !other_active

      entry.report(
        problem_key: :items_blocked_on_closed_tickets,
        detail: "#{entry.issue.key} thinks it's blocked by #{link.other_issue.key}, " \
          "except #{link.other_issue.key} is closed."
      )
    end
  end

  def subtask_label subtask
    "<img src='#{subtask.type_icon_url}' /> #{link_to_issue(subtask)} #{subtask.summary[..50].inspect}"
  end

  def time_as_english(from_time, to_time)
    delta = (to_time - from_time).to_i
    return "#{delta} seconds" if delta < 60

    delta /= 60
    return "#{delta} minutes" if delta < 60

    delta /= 60
    return "#{delta} hours" if delta < 24

    delta /= 24
    "#{delta} days"
  end

  def scan_for_incomplete_subtasks_when_issue_done entry:
    return unless entry.stopped

    subtask_labels = entry.issue.subtasks.filter_map do |subtask|
      subtask_started, subtask_stopped = subtask.board.cycletime.started_stopped_times(subtask)

      if !subtask_started && !subtask_stopped
        "#{subtask_label subtask} (Not even started)"
      elsif !subtask_stopped
        "#{subtask_label subtask} (Still not done)"
      elsif subtask_stopped > entry.stopped
        "#{subtask_label subtask} (Closed #{time_as_english entry.stopped, subtask_stopped} later)"
      end
    end

    return if subtask_labels.empty?

    entry.report(
      problem_key: :incomplete_subtasks_when_issue_done,
      detail: subtask_labels.join('<br />')
    )
  end

  def label_issues number
    return '1 item' if number == 1

    "#{number} items"
  end

  def scan_for_discarded_data entry:
    hash = @discarded_changes_data&.find { |a| a[:issue] == entry.issue }
    return if hash.nil?

    old_start_time = hash[:original_start_time]
    cutoff_time = hash[:cutoff_time]

    old_start_date = old_start_time.to_date
    cutoff_date = cutoff_time.to_date

    days_ignored = (cutoff_date - old_start_date).to_i + 1
    message = "Started: #{old_start_date}, Discarded: #{cutoff_date}, Ignored: #{label_days days_ignored}"

    # If days_ignored is zero then we don't really care as it won't affect any of the calculations.
    return if days_ignored == 1

    entry.report(
      problem_key: :discarded_changes,
      detail: message
    )
  end

  def scan_for_issues_on_multiple_boards entries:
    grouped_entries = entries.group_by { |entry| entry.issue.key }
    grouped_entries.each_value do |entry_list|
      next if entry_list.size == 1

      board_names = entry_list.collect { |entry| entry.issue.board.name.inspect }
      entry_list.first.report(
        problem_key: :issue_on_multiple_boards,
        detail: "Found on boards: #{board_names.sort.join(', ')}"
      )
    end
  end

  def render_discarded_changes problems
    <<-HTML
      #{label_issues problems.size} have had information discarded. This configuration is set
      to "reset the clock" if an item is moved back to the backlog after it's been started. This hides important
      information and makes the data less accurate. <b>Moving items back to the backlog is strongly discouraged.</b>
    HTML
  end

  def render_completed_but_not_started problems
    percentage_work_included = ((issues.size - problems.size).to_f / issues.size * 100).to_i
    html = <<-HTML
      #{label_issues problems.size} were discarded from all charts using cycletime (scatterplot, histogram, etc)
      as we couldn't determine when they started.
    HTML
    if percentage_work_included < 85
      html << <<-HTML
        Consider whether looking at only #{percentage_work_included}% of the total data points is enough
        to come to any reasonable conclusions. See <a href="https://unconsciousagile.com/2024/11/19/survivor-bias.html">
        Survivor Bias</a>.
      HTML
    end
    html
  end

  def render_status_changes_after_done problems
    <<-HTML
      #{label_issues problems.size} had a status change after being identified as done. We should question
      whether they were really done at that point or if we stopped the clock too early.
    HTML
  end

  def render_backwards_through_status_categories problems
    <<-HTML
      #{label_issues problems.size} moved backwards across the board, <b>crossing status categories</b>.
      This will almost certainly have impacted timings as the end times are often taken at status category
      boundaries. You should assume that any timing measurements for this item are wrong.
    HTML
  end

  def render_backwords_through_statuses problems
    <<-HTML
      #{label_issues problems.size} moved backwards across the board. Depending where we have set the
      start and end points, this may give us incorrect timing data. Note that these items did not cross
      a status category and may not have affected metrics.
    HTML
  end

  def render_status_not_on_board problems
    <<-HTML
      #{label_issues problems.size} were not visible on the board for some period of time. This may impact
      timings as the work was likely to have been forgotten if it wasn't visible. What does "not visible"
      mean in this context? The issue was in a status that is not mapped to any visible column on the board.
      Look in "unmapped statuses" on your board.
    HTML
  end

  def render_created_in_wrong_status problems
    <<-HTML
      #{label_issues problems.size} were created in a status that is not considered to be some varient
      of To Do. Most likely this means that the issue was created from one of the columns on the board,
      rather than in the backlog. Why Jira allows this is still a mystery.
    HTML
  end

  def render_stopped_before_started problems
    <<-HTML
      #{label_issues problems.size} were stopped before they were started and this will play havoc with
      any cycletime or WIP calculations. The most common case for this is when an item gets closed and
      then moved back into an in-progress status.
    HTML
  end

  def render_issue_not_started_but_subtasks_have problems
    <<-HTML
      #{label_issues problems.size} still showing 'not started' while sub-tasks underneath them have
      started. This is almost always a mistake; if we're working on subtasks, the top level item should
      also have started.
    HTML
  end

  def render_incomplete_subtasks_when_issue_done problems
    <<-HTML
      #{label_issues problems.size} issues were marked as done while subtasks were still not done.
    HTML
  end

  def render_issue_on_multiple_boards problems
    <<-HTML
      For #{label_issues problems.size}, we have an issue that shows up on more than one board. This
      could result in more data points showing up on a chart then there really should be.
    HTML
  end

  def render_items_blocked_on_closed_tickets problems
    <<-HTML
      For #{label_issues problems.size}, the issue is identified as being blocked by another issue. Yet,
      that other issue is already completed so, by definition, it can't still be blocking.
    HTML
  end
end
