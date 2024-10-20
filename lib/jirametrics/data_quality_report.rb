# frozen_string_literal: true

class DataQualityReport < ChartBase
  attr_reader :original_issue_times # For testing purposes only
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

  def initialize original_issue_times
    super()

    @original_issue_times = original_issue_times

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
    end

    scan_for_issues_on_multiple_boards entries: @entries

    entries_with_problems = entries_with_problems()
    return '' if entries_with_problems.empty?

    wrap_and_render(binding, __FILE__)
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

  # Return a format that's easier to assert against
  def testable_entries
    format = '%Y-%m-%d %H:%M:%S %z'
    @entries.collect do |entry|
      [entry.started&.strftime(format) || '', entry.stopped&.strftime(format) || '', entry.issue]
    end
  end

  def entries_with_problems
    @entries.reject { |entry| entry.problems.empty? }
  end

  def category_name_for status_name:, board:
    board.possible_statuses.find { |status| status.name == status_name }&.category_name
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

    status_names = entry.issue.changes.filter_map do |change|
      next unless change.status?

      format_status change.value, board: entry.issue.board
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
    done_status = changes_after_done.shift.value

    return if changes_after_done.empty?

    board = entry.issue.board
    problem = "Completed on #{entry.stopped.to_date} with status #{format_status done_status, board: board}."
    changes_after_done.each do |change|
      problem << " Changed to #{format_status change.value, board: board} on #{change.time.to_date}."
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
        next if entry.issue.board.backlog_statuses.include? change.value_id

        detail = "Status #{format_status change.value, board: board} is not on the board"
        if issue.board.possible_statuses.expand_statuses(change.value).empty?
          detail = "Status #{format_status change.value, board: board} cannot be found at all. Was it deleted?"
        end

        # If it's been moved back to backlog then it's on a different report. Ignore it here.
        detail = nil if backlog_statuses.any? { |s| s.name == change.value }

        entry.report(problem_key: :status_not_on_board, detail: detail) unless detail.nil?
      elsif change.old_value.nil?
        # Do nothing
      elsif index < last_index
        new_category = category_name_for(status_name: change.value, board: board)
        old_category = category_name_for(status_name: change.old_value, board: board)

        if new_category == old_category
          entry.report(
            problem_key: :backwords_through_statuses,
            detail: "Moved from #{format_status change.old_value, board: board}" \
              " to #{format_status change.value, board: board}" \
              " on #{change.time.to_date}"
          )
        else
          entry.report(
            problem_key: :backwards_through_status_categories,
            detail: "Moved from #{format_status change.old_value, board: board}" \
              " to #{format_status change.value, board: board}" \
              " on #{change.time.to_date}, " \
              " crossing from category #{format_status old_category, board: board, is_category: true}" \
              " to #{format_status new_category, board: board, is_category: true}."
          )
        end
      end
      last_index = index || -1
    end
  end

  def scan_for_issues_not_created_in_a_backlog_status entry:, backlog_statuses:
    return if backlog_statuses.empty?

    creation_change = entry.issue.changes.find { |issue| issue.status? }

    return if backlog_statuses.any? { |status| status.id == creation_change.value_id }

    status_string = backlog_statuses.collect { |s| format_status s.name, board: entry.issue.board }.join(', ')
    entry.report(
      problem_key: :created_in_wrong_status,
      detail: "Created in #{format_status creation_change.value, board: entry.issue.board}, " \
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
    hash = @original_issue_times[entry.issue]
    return if hash.nil?

    old_start_time = hash[:started_time]
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
end
