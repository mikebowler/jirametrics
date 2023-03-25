# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkBarChart < ChartBase
  @@next_id = 0

  def initialize block = nil
    super()

    header_text 'Aging Work Bar Chart'
    description_text <<-HTML
      <p>
        This chart shows all active (started but not completed) work, ordered from oldest at the top to
        newest at the bottom.
      </p>
      <p>
        The colours indicate different statuses, grouped by status category. Any statuses in the status
        category of "To Do" will be in a shade of blue. Any in the category of "In Progress" will be in a
        shade of yellow and any in "Done" will be in a shade of green. Depending on how you calculate
        cycletime, you may end up with only yellows or you may have a mix of all three.
      </p>
      <p>
        The gray backgrounds indicate weekends and the red vertical line indicates the 85% point for all
        items in this time period. Anything that started to the left of that is now an outlier.
      </p>
    HTML

    instance_eval(&block) if block
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
      issue_start_date = cycletime.started_time(issue).to_date
      issue_label = "[#{label_days cycletime.age(issue, today: today)}] #{issue.key}: #{issue.summary}"[0..60]
      [
        status_data_sets(issue: issue, label: issue_label, today: today),
        data_set_by_block(
          issue: issue,
          issue_label: issue_label,
          title_label: 'Blocked',
          stack: 'blocked',
          color: '#FF7400',
          start_date: issue_start_date
        ) { |day| issue.blocked_on_date? day },
        data_set_by_block(
          issue: issue,
          issue_label: issue_label,
          title_label: 'Stalled',
          stack: 'blocked',
          color: 'orange',
          start_date: issue_start_date
        ) { |day| issue.stalled_on_date?(day) && !issue.blocked_on_date?(day) },
        data_set_by_block(
          issue: issue,
          issue_label: issue_label,
          title_label: 'Expedited',
          stack: 'expedited',
          color: 'red',
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
          borderColor: 'white',
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

  def data_set_by_block(
    issue:, issue_label:, title_label:, stack:, color:, start_date:, end_date: date_range.end, &block
  )
    started = nil
    ended = nil
    data = []

    (start_date..end_date).each do |day|
      if block.call(day)
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

    return nil if data.empty?

    {
      type: 'bar',
      data: data,
      backgroundColor: color,
      stacked: true,
      stack: stack
    }
  end

  def calculate_percent_line percentage: 85
    days = completed_issues_in_range.collect { |issue| issue.board.cycletime.cycletime(issue) }.compact.sort
    return nil if days.empty?

    days[days.length * percentage / 100]
  end
end
