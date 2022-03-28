# frozen_string_literal: true

require './lib/chart_base'

class ExpeditedChart < ChartBase
  EXPEDITED_SEGMENT = Object.new.tap do |segment|
    def segment.to_json *_args
      <<-SNIPPET
{
  borderColor: ctx => expedited(ctx, 'red') || notExpedited(ctx, 'gray'),
  borderDash: ctx => notExpedited(ctx, [6, 6])
}
      SNIPPET
    end
  end

  attr_accessor :issues, :cycletime, :board_columns, :possible_statuses, :date_range
  attr_reader :expedited_label

  def initialize priority_name
    super()
    @expedited_label = priority_name
  end

  def run
    data_sets = find_expedited_issues.collect do |issue|
      make_expedite_lines_data_set(issue: issue, expedite_data: prepare_expedite_data(issue))
    end

    render(binding, __FILE__)
  end

  def prepare_expedite_data issue
    expedite_start = nil
    result = []

    issue.changes.each do |change|
      next unless change.priority?

      if change.value == expedited_label
        expedite_start = change.time
      elsif expedite_start
        start_date = expedite_start.to_date
        stop_date = change.time.to_date

        if date_range.include?(start_date) || date_range.include?(stop_date) ||
           (start_date < date_range.begin && stop_date > date_range.end)

          result << [expedite_start, :expedite_start]
          result << [change.time, :expedite_stop]
        end
        expedite_start = nil
      end
    end

    # If expedite_start is still set then we never ended.
    result << [expedite_start, :expedite_start] if expedite_start
    result
  end

  def find_expedited_issues
    expedited_issues = @issues.reject do |issue|
      prepare_expedite_data(issue).empty?
    end

    expedited_issues.sort { |a, b| a.key_as_i <=> b.key_as_i }
  end

  def later_date date1, date2
    return date1 if date2.nil?
    return date2 if date1.nil?

    [date1, date2].max
  end

  def make_point issue:, time:, label:, expedited:
    {
      y: (time.to_date - issue.created.to_date).to_i + 1,
      x: time.to_date.to_s,
      title: ["#{issue.key} #{label} : #{issue.summary}"],
      expedited: (expedited ? 1 : 0)
    }
  end

  def make_expedite_lines_data_set issue:, expedite_data:
    started_time = @cycletime.started_time(issue)
    stopped_time = @cycletime.stopped_time(issue)

    expedite_data << [started_time, :issue_started] if started_time
    expedite_data << [stopped_time, :issue_stopped] if stopped_time
    expedite_data.sort! { |a, b| a[0] <=> b[0] }

    data = []
    dot_colors = []
    point_styles = []
    expedited = false

    expedite_data.each do |time, action|
      case action
      when :issue_started
        data << make_point(issue: issue, time: time, label: 'Started', expedited: expedited)
        dot_colors << 'orange'
        point_styles << 'rect'
      when :issue_stopped
        data << make_point(issue: issue, time: time, label: 'Completed', expedited: expedited)
        dot_colors << 'green'
        point_styles << 'rect'
      when :expedite_start
        data << make_point(issue: issue, time: time, label: 'Expedited', expedited: true)
        dot_colors << 'red'
        point_styles << 'circle'
        expedited = true
      when :expedite_stop
        data << make_point(issue: issue, time: time, label: 'Not expedited', expedited: false)
        dot_colors << 'gray'
        point_styles << 'circle'
        expedited = false
      else
        raise "Unexpected action: #{action}"
      end
    end

    unless expedite_data.empty?
      last_change_time = expedite_data[-1][0].to_date
      if last_change_time && last_change_time <= date_range.end && stopped_time.nil?
        data << make_point(issue: issue, time: date_range.end, label: 'Still ongoing', expedited: expedited)
        dot_colors << 'blue' # It won't be visible so it doesn't matter
        point_styles << 'dash'
      end
    end

    {
      type: 'line',
      label: issue.key,
      data: data,
      fill: false,
      showLine: true,
      backgroundColor: dot_colors,
      pointBorderColor: 'black',
      pointStyle: point_styles,
      segment: EXPEDITED_SEGMENT
    }
  end
end
