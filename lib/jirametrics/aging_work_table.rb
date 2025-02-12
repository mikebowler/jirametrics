# frozen_string_literal: true

require 'jirametrics/chart_base'

class AgingWorkTable < ChartBase
  attr_accessor :today # , :board_id
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
    @today = date_range.end
    aging_issues = select_aging_issues + expedited_but_not_started

    wrap_and_render(binding, __FILE__)
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

  def forecasted_days_remaining_and_message issue
    calculator = BoardMovementCalculator.new board: current_board, issues: issues
    column_name, entry_time = calculator.find_current_column_and_entry_time_in_column issue
    return [nil, 'This issue is not visible on the board. No way to predict when it will be done.'] if column_name.nil?

    @likely_age_data = calculator.age_data_for percentage: 85

    # TODO: This calculation is wrong. See birch samples
    age_in_column = (date_range.end - entry_time.to_date).to_i + 1

    message = nil
    column_index = current_board.visible_columns.index { |c| c.name == column_name }

    last_non_zero_datapoint = @likely_age_data.reverse.find { |d| !d.zero? }
    remaining_in_current_column = @likely_age_data[column_index] - age_in_column
    if remaining_in_current_column.negative?
      message = 'This item is an outlier. The actual time will likely be much greater than the forecast.'
      remaining_in_current_column = 0
    end

    forecasted_days = last_non_zero_datapoint - @likely_age_data[column_index] + remaining_in_current_column
    # puts "#{issue.key} data: #{@likely_age_data}, last: #{last_non_zero_datapoint}, column_index: #{column_index}, " \
    #   "age_in_column: #{age_in_column}, forecast: #{forecasted_days}"

    [forecasted_days, message]
  end

  def dates_text issue
    color = nil
    title = nil

    date = date_range.end
    due = issue.due_date
    return '' unless due

    if date == due
      color = '--aging-work-table-date-in-jeopardy'
      title = 'Item is due today and is still in progress'
    elsif date > due
      color = '--aging-work-table-date-overdue'
      title = 'Item is already overdue.'
    else
      # Try to forecast the end date
      days_remaining, message = forecasted_days_remaining_and_message issue
      if message
        color = '--aging-work-table-date-in-jeopardy'
        title = message
      elsif date_range.end + days_remaining > due
        color = '--aging-work-table-date-in-jeopardy'
        due_days_label = label_days (due - date_range.end).to_i
        title = "Likely to need another #{days_remaining} days and it's due in #{due_days_label}"
      end
    end

    result = +''
    result << color_block(color)
    result << ' '
    result << due.to_s
    result << "<br /><span style='font-size: 0.8em'>#{title}</span>" if title
    result
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
