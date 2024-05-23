# frozen_string_literal: true

require 'jirametrics/chart_base'

class AgingWorkBarChart < ChartBase
  @@next_id = 0

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
    aging_issues = @issues.select do |issue|
      cycletime = issue.board.cycletime
      cycletime.started_time(issue) && cycletime.stopped_time(issue).nil?
    end

    grow_chart_height_if_too_many_issues aging_issues.size

    today = date_range.end
    aging_issues.sort! do |a, b|
      a.board.cycletime.age(b, today: today) <=> b.board.cycletime.age(a, today: today)
    end
    data_sets = []
    aging_issues.each do |issue|
      cycletime = issue.board.cycletime
      issue_start_time = cycletime.started_time(issue)
      issue_start_date = issue_start_time.to_date
      issue_label = "[#{label_days cycletime.age(issue, today: today)}] #{issue.key}: #{issue.summary}"[0..60]
      [
        status_data_sets(issue: issue, label: issue_label, today: today),
        blocked_data_sets(
          issue: issue,
          issue_label: issue_label,
          stack: 'blocked',
          issue_start_time: issue_start_time
        ),
        data_set_by_block(
          issue: issue,
          issue_label: issue_label,
          title_label: 'Expedited',
          stack: 'expedited',
          color: CssVariable['--expedited-color'],
          start_date: issue_start_date
        ) { |day| issue.expedited_on_date?(day) }
      ].compact.flatten.each do |data|
        data_sets << data
      end
    end

    percentage = calculate_percent_line
    percentage_line_x = date_range.end - calculate_percent_line if percentage

    wrap_and_render(binding, __FILE__)
  end

  def grow_chart_height_if_too_many_issues aging_issue_count
    px_per_bar = 8
    bars_per_issue = 3
    preferred_height = aging_issue_count * px_per_bar * bars_per_issue
    @canvas_height = preferred_height if @canvas_height.nil? || @canvas_height < preferred_height
  end

  def status_data_sets issue:, label:, today:
    cycletime = issue.board.cycletime

    issue_started_time = cycletime.started_time(issue)

    previous_start = nil
    previous_status = nil

    data_sets = []
    issue.changes.each do |change|
      next unless change.status?

      status = issue.find_status_by_name change.value

      unless previous_start.nil? || previous_start < issue_started_time
        hash = {
          type: 'bar',
          data: [{
            x: [chart_format(previous_start), chart_format(change.time)],
            y: label,
            title: "#{issue.type} : #{change.value}"
          }],
          backgroundColor: status_category_color(status),
          borderColor: CssVariable['--aging-work-bar-chart-separator-color'],
          borderWidth: {
             top: 0,
             right: 1,
             bottom: 0,
             left: 0
          },
          stacked: true,
          stack: 'status'
        }
        data_sets << hash if date_range.include?(change.time.to_date)
      end

      previous_start = change.time
      previous_status = status
    end

    if previous_start
      data_sets << {
        type: 'bar',
        data: [{
          x: [chart_format(previous_start), chart_format("#{today}T00:00:00#{@timezone_offset}")],
          y: label,
          title: "#{issue.type} : #{previous_status.name}"
        }],
        backgroundColor: status_category_color(previous_status),
        stacked: true,
        stack: 'status'
      }
    end

    data_sets
  end

  def one_block_change_data_set starting_change:, ending_time:, issue_label:, stack:, issue_start_time:
    deprecated message: 'blocked color should be set via css now', date: '2024-05-03' if settings['blocked_color']
    deprecated message: 'blocked color should be set via css now', date: '2024-05-03' if settings['stalled_color']

    color = settings['blocked_color'] || '--blocked-color'
    color = settings['stalled_color'] || '--stalled-color' if starting_change.stalled?
    {
      backgroundColor: CssVariable[color],
      data: [
        {
          title: starting_change.reasons,
          x: [chart_format([issue_start_time, starting_change.time].max), chart_format(ending_time)],
          y: issue_label
        }
      ],
      stack: stack,
      stacked: true,
      type: 'bar'
    }
  end

  def blocked_data_sets issue:, issue_label:, issue_start_time:, stack:
    data_sets = []
    starting_change = nil

    issue.blocked_stalled_changes(end_time: time_range.end).each do |change|
      if starting_change.nil? || starting_change.active?
        starting_change = change
        next
      end

      if change.time >= issue_start_time
        data_sets << one_block_change_data_set(
          starting_change: starting_change, ending_time: change.time,
          issue_label: issue_label, stack: stack, issue_start_time: issue_start_time
        )
      end

      starting_change = change
    end

    data_sets
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
