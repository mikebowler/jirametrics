# frozen_string_literal: true

require 'jirametrics/chart_base'
require 'jirametrics/bar_chart_range'

class AgingWorkBarChart < ChartBase
  def initialize block
    super()

    header_text 'Aging Work Bar Chart'
    description_text <<-HTML
      <p>
        This chart shows all active (started but not completed) work, ordered from oldest at the top to
        newest at the bottom.
      </p>
      <p>
        There are potentially three bars for each issue, although a bar may be missing if the issue has no
        information relevant to that. Hovering over any of the bars will provide more details.
        <ol>
          <li>The top bar tells you what status the issue is in at any time. The colour indicates the
          status category, which will be one of #{color_block '--status-category-todo-color'} To Do,
          #{color_block '--status-category-inprogress-color'} In Progress,
          or #{color_block '--status-category-done-color'} Done</li>
          <li>The middle bar indicates #{color_block '--blocked-color'} blocked
          or #{color_block '--stalled-color'} stalled.</li>
          <li>The bottom bar indicated #{color_block '--expedited-color'} expedited.</li>
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
    issue_start_time, _stopped_time = cycletime.started_stopped_times(issue)
    issue_start_date = issue_start_time.to_date
    issue_label = "[#{label_days cycletime.age(issue, today: today)}] #{issue.key}: #{issue.summary}"[0..60]
    [
      status_data_sets(issue: issue, label: issue_label, today: today, issue_start_time: issue_start_time),
      bar_chart_range_to_data_set(
        y_value: issue_label, stack: 'blocked', issue_start_time: issue_start_time,
        ranges: blocked_stalled_active_data_sets(issue: issue, issue_start_time: issue_start_time)
      ),
      data_set_by_block(
        issue: issue,
        issue_label: issue_label,
        title_label: 'Expedited',
        stack: 'expedited',
        color: CssVariable['--expedited-color'],
        start_date: issue_start_date
      ) { |day| issue.expedited_on_date?(day) }
    ]
  end

  def sort_by_age! issues:, today:
    issues.sort! do |a, b|
      b.board.cycletime.age(b, today: today) <=> a.board.cycletime.age(a, today: today)
    end
  end

  def select_aging_issues issues:
    issues.select do |issue|
      started_time, stopped_time = issue.board.cycletime.started_stopped_times(issue)
      started_time && stopped_time.nil?
    end
  end

  def grow_chart_height_if_too_many_issues aging_issue_count:
    px_per_bar = 8
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

  def status_data_sets issue:, label:, today:, issue_start_time:
    end_of_today = Time.parse("#{today}T23:59:59#{@timezone_offset}")
    ranges = collect_status_ranges issue: issue, now: end_of_today
    bar_chart_range_to_data_set y_value: label, ranges: ranges, stack: 'status', issue_start_time: issue_start_time
  end

  def bar_chart_range_to_data_set y_value:, ranges:, stack:, issue_start_time:
    ranges.filter_map do |bar_chart_range|
      next if bar_chart_range.stop < issue_start_time

      {
        type: 'bar',
        data: [{
          x: [chart_format([bar_chart_range.start, issue_start_time].max), chart_format(bar_chart_range.stop)],
          y: y_value,
          title: bar_chart_range.title
        }],
        backgroundColor: bar_chart_range.color,
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

  def blocked_stalled_active_data_sets issue:, issue_start_time:
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

  def data_set_by_block(
    issue:, issue_label:, title_label:, stack:, color:, start_date:, end_date: date_range.end
  )
    started = nil
    ended = nil
    data = []

    (start_date..end_date).each do |day|
      if yield(day)
        started = day if started.nil?
        ended = day
      elsif ended
        data << {
          x: [chart_format(started), chart_format(ended)],
          y: issue_label,
          title: "#{issue.type} : #{title_label} #{label_days (ended - started).to_i + 1}"
        }

        started = nil
        ended = nil
      end
    end

    if started
      data << {
        x: [chart_format(started), chart_format(ended)],
        y: issue_label,
        title: "#{issue.type} : #{title_label} #{label_days (end_date - started).to_i + 1}"
      }
    end

    return [] if data.empty?

    {
      type: 'bar',
      data: data,
      backgroundColor: color,
      stacked: true,
      stack: stack
    }
  end

  def calculate_percent_line percentage: 85
    days = completed_issues_in_range.filter_map { |issue| issue.board.cycletime.cycletime(issue) }.sort
    return nil if days.empty?

    days[days.length * percentage / 100]
  end
end
