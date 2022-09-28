# frozen_string_literal: true

class DataQualityChecker
  attr_accessor :issues, :cycletime, :board, :possible_statuses

  class Entry
    attr_reader :started, :stopped, :issue, :problems

    def initialize started:, stopped:, issue:
      @started = started
      @stopped = stopped
      @issue = issue
      @problems = []
    end

    def report problem_key: nil, detail: nil, problem: nil, impact: nil
      @problems << [problem_key, detail, problem, impact]
    end
  end

  def run
    initialize_entries

    backlog_statuses = @possible_statuses.expand_statuses board.backlog_statuses

    @entries.each do |entry|
      scan_for_completed_issues_without_a_start_time entry: entry
      scan_for_status_change_after_done entry: entry
      scan_for_backwards_movement entry: entry, backlog_statuses: backlog_statuses
      scan_for_issues_not_created_in_the_right_status entry: entry
      scan_for_stopped_before_started entry: entry
      # scan_for_issues_not_started_with_subtasks_that_have entry: entry
    end

    entries_with_problems = entries_with_problems()
    return '' if entries_with_problems.empty?
  end

  def problems_for key
    result = []
    @entries.each do |entry|
      entry.problems.each do |problem_key, detail|
        result << [entry.issue, detail] if problem_key == key
      end
    end
    result
  end

  # Return a format that's easier to assert against
  def testable_entries
    @entries.collect { |entry| [entry.started.to_s, entry.stopped.to_s, entry.issue] }
  end

  def entries_with_problems
    @entries.reject { |entry| entry.problems.empty? }
  end

  def category_name_for status_name:
    @possible_statuses.find { |status| status.name == status_name }&.category_name
  end

  def initialize_entries
    @entries = @issues.collect do |issue|
      Entry.new(
        started: @cycletime.started_time(issue),
        stopped: @cycletime.stopped_time(issue),
        issue: issue
      )
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

    changes = entry.issue.changes.select { |change| change.status? && change.time == entry.stopped }
    detail = 'No status changes found at the time that this item was marked completed.'
    unless changes.empty?
      detail = changes.collect do |change|
        "Status changed from #{format_status change.old_value} to #{format_status change.value} on #{change.time}."
      end.join ' '
    end

    entry.report(
      problem_key: :completed_but_not_started,
      detail: detail
    )
  end

  def scan_for_status_change_after_done entry:
    return unless entry.stopped

    changes_after_done = entry.issue.changes.select do |change|
      change.status? && change.time > entry.stopped
    end

    return if changes_after_done.empty?

    problem = "This item was done on #{entry.stopped} but status changes continued after that."
    changes_after_done.each do |change|
      problem << " Status change to #{format_status change.value} on #{change.time}."
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

      index = board.visible_columns.find_index { |column| column.status_ids.include? change.value_id }
      if index.nil?
        detail = "Status #{format_status change.value} is not on the board"
        if @possible_statuses.expand_statuses(change.value).empty?
          detail = "Status #{format_status change.value} cannot be found at all. Was it deleted?"
        end

        # If it's been moved back to backlog then it's on a different report. Ignore it here.
        detail = nil if backlog_statuses.any? { |s| s.name == change.value }

        entry.report(problem_key: :status_not_on_board, detail: detail) unless detail.nil?
      elsif change.old_value.nil?
        # Do nothing
      elsif index < last_index
        new_category = category_name_for(status_name: change.value)
        old_category = category_name_for(status_name: change.old_value)

        if new_category == old_category
          entry.report(
            problem_key: :backwords_through_statuses,
            detail: "The issue moved backwards from #{format_status change.old_value}" \
              " to #{format_status change.value}" \
              " on #{change.time.to_date}"
          )
        else
          entry.report(
            problem_key: :backwards_through_status_categories,
            detail: "The issue moved backwards from #{format_status change.old_value}" \
              " to #{format_status change.value}" \
              " on #{change.time.to_date}, " \
              " crossing status categories from #{format_status old_category, is_category: true}" \
              " to #{format_status new_category, is_category: true}."
          )
        end
      end
      last_index = index || -1
    end
  end

  # TODO: this is probably wanting the backlog statuses
  def scan_for_issues_not_created_in_the_right_status entry:
    valid_initial_status_ids = board.backlog_statuses
    return if valid_initial_status_ids.empty?

    creation_change = entry.issue.changes.find { |issue| issue.status? }

    return if valid_initial_status_ids.include? creation_change.value_id

    entry.report(
      problem_key: :created_in_wrong_status,
      detail: "Issue was created in #{format_status creation_change.value} status on #{creation_change.time.to_date}"
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
      started_subtasks << subtask if @cycletime.started_time(subtask)
    end

    return if started_subtasks.empty?

    entry.report(
      problem_key: :issue_not_started_but_subtasks_have,
      detail: "The following subtasks have started: #{started_subtasks.collect(&:key).join(', ')}"
    )
  end

  def format_status name_or_id, is_category: false
    statuses = @possible_statuses.expand_statuses([name_or_id])
    raise "Expected exactly one match and got #{statuses.inspect} for #{name_or_id.inspect}" if statuses.size > 1

    return "<span style='color: red'>#{name_or_id}</span>" if statuses.empty?

    status = statuses.first
    color = case status.category_name
    when nil then 'black'
    when 'To Do' then 'gray'
    when 'In Progress' then 'blue'
    when 'Done' then 'green'
    else 'red'
    end

    text = is_category ? status.category_name : status.name
    "<span style='color: #{color}'>#{text}</span>"
  end
end
