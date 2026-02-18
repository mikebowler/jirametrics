# frozen_string_literal: true

require 'jirametrics/chart_base'
require 'jirametrics/bar_chart_range'

class AgingWorkBarChart < ChartBase
  def initialize block
    super()

    @age_cutoff = nil
    header_text 'Aging Work Bar Chart'
    description_text <<-HTML
      <p>
        This chart shows all active (started but not completed) work, ordered from oldest at the top to
        newest at the bottom.
      </p>
      <p>
        There are three bars for each issue, and hovering over any of the bars will provide more details.
        <ol>
          <li>Status: The status the issue was in at any time. The colour indicates the
          status category, which will be one of #{color_block '--status-category-todo-color'} To Do,
          #{color_block '--status-category-inprogress-color'} In Progress,
          or #{color_block '--status-category-done-color'} Done</li>
          <li>Activity: This bar indicates #{color_block '--blocked-color'} blocked
          or #{color_block '--stalled-color'} stalled.</li>
          <li>Priority: This shows the priority over time. If one of these priorities is considered expedited
          then it will be drawn with diagonal lines.</li>
        </ol>
      </p>
      #{describe_non_working_days}
    HTML

    # Because this one will size itself as needed, we start with a smaller default size
    @canvas_height = 80

    instance_eval(&block)
  end

  def run
    aging_issues = select_aging_issues issues: @issues
    adjust_time_date_ranges_to_start_from_earliest_issue_start(aging_issues)

    today = date_range.end
    sort_by_age! issues: aging_issues, today: today

    grow_chart_height_if_too_many_issues aging_issue_count: aging_issues.size

    data_sets = aging_issues
      .collect { |issue| data_sets_for_one_issue issue: issue, today: today }
      .flatten
      .compact

    percentage = calculate_percent_line
    percentage_line_x = date_range.end - calculate_percent_line if percentage

    if aging_issues.empty?
      @description_text = '<p>There is no aging work</p>'
      return render_top_text(binding)
    end

    wrap_and_render(binding, __FILE__)
  end

  def adjust_time_date_ranges_to_start_from_earliest_issue_start aging_issues
    earliest_start_time = aging_issues.collect do |issue|
      issue.board.cycletime.started_stopped_times(issue).first
    end.min
    return if earliest_start_time.nil? || earliest_start_time >= @time_range.begin

    @time_range = earliest_start_time..@time_range.end
    @date_range = @time_range.begin.to_date..@time_range.end.to_date
  end

  def data_sets_for_one_issue issue:, today:
    cycletime = issue.board.cycletime
    issue_start_time = cycletime.started_stopped_times(issue).first
    end_of_today = Time.parse("#{today}T23:59:59#{@timezone_offset}")

    bar_data = [
      ['status', collect_status_ranges(issue: issue, now: end_of_today)],
      ['blocked', collect_blocked_stalled_ranges(issue: issue, issue_start_time: issue_start_time)],
      ['priority', collect_priority_ranges(issue: issue)]
    ]

    issue_label = "[#{label_days cycletime.age(issue, today: today)}] #{issue.key}: #{issue.summary}"[0..60]
    bar_data.collect do |stack, ranges|
      bar_chart_range_to_data_set y_value: issue_label, ranges: ranges, stack: stack, issue_start_time: issue_start_time
    end
  end

  def sort_by_age! issues:, today:
    issues.sort! do |a, b|
      b.board.cycletime.age(b, today: today) <=> a.board.cycletime.age(a, today: today)
    end
  end

  def select_aging_issues issues:
    issues.select do |issue|
      started_time, stopped_time = issue.board.cycletime.started_stopped_times(issue)
      next false unless started_time && stopped_time.nil?

      age = (date_range.end - started_time.to_date).to_i + 1
      !(@age_cutoff && @age_cutoff < age)
    end
  end

  def grow_chart_height_if_too_many_issues aging_issue_count:
    px_per_bar = 10
    bars_per_issue = 3
    preferred_height = aging_issue_count * px_per_bar * bars_per_issue
    @canvas_height = preferred_height if @canvas_height.nil? || @canvas_height < preferred_height
  end

  def collect_status_ranges issue:, now:
    ranges = []
    issue_started_time = issue.board.cycletime.started_stopped_times(issue).first
    previous_start = nil
    previous_status = nil
    issue.status_changes.each do |change|
      new_status = issue.find_or_create_status id: change.value_id, name: change.value
      if previous_start.nil?
        previous_start = change.time
        previous_status = new_status
        next
      end

      previous_start = issue_started_time if issue_started_time > previous_start

      ranges << BarChartRange.new(
        start: previous_start,
        stop: change.time,
        color: status_category_color(previous_status),
        title: previous_status.to_s
      )
      previous_start = change.time
      previous_status = new_status
    end

    ranges << BarChartRange.new(
      start: previous_start,
      stop: now,
      color: status_category_color(previous_status),
      title: previous_status.to_s
    )
    ranges
  end

  def bar_chart_range_to_data_set y_value:, ranges:, stack:, issue_start_time:
    ranges.filter_map do |bar_chart_range|
      next if bar_chart_range.stop < issue_start_time

      background_color = bar_chart_range.color
      if bar_chart_range.highlight
        background_color = RawJavascript.new("createDiagonalPattern(#{background_color.to_json})")
      end

      {
        type: 'bar',
        data: [{
          x: [chart_format([bar_chart_range.start, issue_start_time].max), chart_format(bar_chart_range.stop)],
          y: y_value,
          title: bar_chart_range.title
        }],
        backgroundColor: background_color,
        borderColor: CssVariable['--aging-work-bar-chart-separator-color'],
        borderWidth: {
           top: 0,
           right: 1,
           bottom: 0,
           left: 0
        },
        stacked: true,
        stack: stack
      }
    end
  end

  def collect_blocked_stalled_ranges issue:, issue_start_time:
    results = []
    starting_change = nil

    issue.blocked_stalled_changes(end_time: time_range.end).each do |change|
      if starting_change.nil? || starting_change.active?
        starting_change = change
        next
      end

      if change.time >= issue_start_time
        color = settings['blocked_color'] || '--blocked-color'
        color = settings['stalled_color'] || '--stalled-color' if starting_change.stalled?

        results << BarChartRange.new(
          start: starting_change.time, stop: change.time, color: CssVariable[color], title: starting_change.reasons
        )
      end

      starting_change = change
    end
    results
  end

  def collect_priority_ranges issue:
    expedited_priority_names = settings['expedited_priority_names']

    previous_change = nil
    results = []

    issue.changes.each do |change|
      next unless change.priority?

      if previous_change.nil?
        previous_change = change
        next
      end

      results << create_range_for_priority(
        previous_change: previous_change, stop_time: change.time,
        expedited_priority_names: expedited_priority_names
      )
      previous_change = change
    end

    results << create_range_for_priority(
      previous_change: previous_change, stop_time: time_range.end,
      expedited_priority_names: expedited_priority_names
    )
    results
  end

  def create_range_for_priority previous_change:, stop_time:, expedited_priority_names:
    expedited = expedited_priority_names.include?(previous_change.value)
    title = "Priority: #{previous_change.value}"
    title << ' (expedited)' if expedited

    BarChartRange.new(
      start: previous_change.time,
      stop: stop_time,
      color: CssVariable["--priority-color-#{previous_change.value.downcase.gsub(/\s/, '')}"],
      title: title,
      highlight: expedited
    )
  end

  def calculate_percent_line percentage: 85
    days = completed_issues_in_range.filter_map { |issue| issue.board.cycletime.cycletime(issue) }.sort
    return nil if days.empty?

    days[days.length * percentage / 100]
  end

  def age_cutoff days
    @age_cutoff = days
  end
end
