# frozen_string_literal: true

require 'jirametrics/chart_base'

class AgingWorkTable < ChartBase
  attr_accessor :today
  attr_reader :any_scrum_boards

  def initialize block
    super()
    @stalled_threshold = 5
    @dead_threshold = 45
    @age_cutoff = 0

    header_text 'Aging Work Table'
    description_text <<-TEXT
      <p>
        This chart shows all active (started but not completed) work, ordered from oldest at the top to
        newest at the bottom.
      </p>
      <p>
        If there are expedited items that haven't yet started then they're at the bottom of the table.
        By the very definition of expedited, if we haven't started them already, we'd better get on that.
      </p>
      <p>
        Legend:
        <ul><li><b>FD:</b> <b>F</b>orecasted <b>D</b>ays remaining. A hint of how long it will likely take
        to complete, based on historical data for this same board.</li>
        <li><b>E:</b> Whether this item is <b>E</b>xpedited.</li>
        <li><b>B/S:</b> Whether this item is either <b>B</b>locked or <b>S</b>talled.</li>
        </ul>
      </p>
    TEXT

    instance_eval(&block)
  end

  def run
    initialize_calculator
    aging_issues = select_aging_issues + expedited_but_not_started

    wrap_and_render(binding, __FILE__)
  end

  # This is its own method simply so the tests can initialize the calculator without doing a full run.
  def initialize_calculator
    @today = date_range.end
    @calculator = BoardMovementCalculator.new board: current_board, issues: issues, today: @today
  end

  def expedited_but_not_started
    @issues.select do |issue|
      started_time, stopped_time = issue.board.cycletime.started_stopped_times(issue)
      started_time.nil? && stopped_time.nil? && issue.expedited?
    end.sort_by(&:created)
  end

  def select_aging_issues
    aging_issues = @issues.select do |issue|
      cycletime = issue.board.cycletime
      started, stopped = cycletime.started_stopped_times(issue)
      next false if started.nil? || stopped
      next true if issue.blocked_on_date?(@today, end_time: time_range.end) || issue.expedited?

      age = (@today - started.to_date).to_i + 1
      age > @age_cutoff
    end
    @any_scrum_boards = aging_issues.any? { |issue| issue.board.scrum? }
    aging_issues.sort { |a, b| b.board.cycletime.age(b, today: @today) <=> a.board.cycletime.age(a, today: @today) }
  end

  def expedited_text issue
    return unless issue.expedited?

    name = issue.raw['fields']['priority']['name']
    color_block '--expedited-color', title: "Expedited: Has a priority of &quot;#{name}&quot;"
  end

  def blocked_text issue
    started_time, _stopped_time = issue.board.cycletime.started_stopped_times(issue)
    return nil if started_time.nil?

    current = issue.blocked_stalled_changes(end_time: time_range.end)[-1]
    if current.blocked?
      color_block '--blocked-color', title: current.reasons
    elsif current.stalled?
      if current.stalled_days && current.stalled_days > @dead_threshold
        color_block(
          '--dead-color',
          title: "Dead? Hasn&apos;t had any activity in #{label_days current.stalled_days}. " \
            'Does anyone still care about this?'
        )
      else
        color_block '--stalled-color', title: current.reasons
      end
    end
  end

  def fix_versions_text issue
    issue.fix_versions.collect do |fix|
      if fix.released?
        icon_text = icon_span title: 'Released. Likely not on the board anymore.', icon: '✅'
        "#{fix.name} #{icon_text}"
      else
        fix.name
      end
    end.join('<br />')
  end

  def sprints_text issue
    sprint_ids = []

    issue.changes.each do |change|
      next unless change.sprint?

      sprint_ids << change.raw['to'].split(/\s*,\s*/).collect { |id| id.to_i }
    end
    sprint_ids.flatten!

    issue.board.sprints.select { |s| sprint_ids.include? s.id }.collect do |sprint|
      icon_text = nil
      if sprint.active?
        icon_text = icon_span title: 'Active sprint', icon: '➡️'
      else
        icon_text = icon_span title: 'Sprint closed', icon: '✅'
      end
      "#{sprint.name} #{icon_text}"
    end.join('<br />')
  end

  def dates_text issue
    date = date_range.end
    due = issue.due_date

    days_remaining, message = @calculator.forecasted_days_remaining_and_message issue: issue, today: @today

    return message if message
    return "Likely #{label_days days_remaining} remaining." unless due


    if due < date
      "<b>Already overdue</b>. It was supposed to be complete on #{due}"
    elsif due == date
      '<b>Due today</b> and will likely be finished on time'
    elsif date_range.end + days_remaining > due
      "<b>Due in #{label_days (due - date_range.end).to_i}</b> but is likley to still need #{label_days days_remaining}."
    else
      "<b>Due in #{label_days (due - date_range.end).to_i}</b> and is likely to complete on time."
    end
  end

  def age_cutoff age = nil
    @age_cutoff = age.to_i if age
    @age_cutoff
  end

  def parent_hierarchy issue
    result = []

    while issue
      cyclical_parent_links = result.include? issue
      result << issue

      break if cyclical_parent_links

      issue = issue.parent
    end

    result.reverse
  end
end
