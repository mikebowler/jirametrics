# frozen_string_literal: true

require './lib/chart_base'

class ExpeditedChart < ChartBase
  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses, :date_range
  attr_reader :expedited_label

  def initialize priority_name
    @expedited_label = priority_name
  end

  def run
    expedited_issues = @issues.select do |issue|
      issue.changes.any? { |change| change.priority? && change.value == expedited_label }
    end

    data_sets = []
    expedited_issues.each do |issue|
      data_sets << make_expedite_lines_data_set(issue: issue)
    end

    render(binding, __FILE__)
  end

  def later_date date1, date2
    return date1 if date2.nil?
    return date2 if date1.nil?

    [date1, date2].max
  end

  def make_point issue:, time:, label:
    {
      y: (time.to_date - issue.created.to_date).to_i + 1,
      x: time.to_date.to_s,
      title: ["#{issue.key} #{label} : #{issue.summary}"]
    }
  end

  def make_expedite_lines_data_set issue:
    started_time = @cycletime.started_time(issue)
    stopped_time = @cycletime.stopped_time(issue)

    # Although unlikely, it's possible for two statuses to have exactly the same timestamp
    # and we don't want the started/stopped dots showing up multiple times each
    started_dot_inserted = false
    stopped_dot_inserted = false

    data = []
    dot_colors = []
    line_colors = []
    point_styles = []

    expedite_started = nil
    issue.changes.each do |change|
      if change.time == started_time && started_dot_inserted == false
        data << make_point(issue: issue, time: change.time, label: 'Started')
        dot_colors << 'orange'
        point_styles << 'rect'
        started_dot_inserted = true
      end

      if change.time == stopped_time && stopped_dot_inserted == false
        data << make_point(issue: issue, time: change.time, label: 'Completed')
        dot_colors << 'green'
        point_styles << 'rect'
        stopped_dot_inserted = true
      end

      next unless change.priority?

      if change.value == expedited_label
        expedite_started = change.time

        data << make_point(issue: issue, time: later_date(date_range.begin, change.time), label: 'Expedited')
        dot_colors << 'red'
        point_styles << 'dash'
        line_colors << 'red'
      else
        data << make_point(issue: issue, time: later_date(date_range.begin, change.time), label: 'Not expedited')
        dot_colors << 'gray'
        point_styles << 'circle'
        line_colors << 'gray'
        expedite_started = nil
      end
    end

    # If the issue is still open but we've run out of changes to process then fabricate the last dot.
    last_change_time = issue.changes[-1]&.time
    if last_change_time && last_change_time < date_range.end && stopped_dot_inserted == false
      data << make_point(issue: issue, time: date_range.end, label: 'Still ongoing')
      dot_colors << 'blue' # It won't be visible so it doesn't matter
      line_colors = (expedite_started ? 'red' : 'gray')
      point_styles << 'dash'
    end

    {
      type: 'line',
      label: issue.key,
      data: data,
      fill: false,
      showLine: true,
      backgroundColor: dot_colors,
      borderColor: line_colors,
      pointBorderColor: 'black',
      pointStyle: point_styles
    }
  end
end
