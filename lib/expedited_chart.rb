# frozen_string_literal: true

require './lib/chart_base'

class ExpeditedChart < ChartBase
  class ExpeditedSegment
    def to_json *_args
      <<-SNIPPET
{
  borderColor: ctx => expedited(ctx, 'red') || notExpedited(ctx, 'gray'),
  borderDash: ctx => notExpedited(ctx, [6, 6])
}
      SNIPPET
    end
  end

  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses, :date_range
  attr_reader :expedited_label

  def initialize priority_name
    super()
    @expedited_label = priority_name
  end

  def run
    expedited_issues = @issues.select do |issue|
      expedited_during_date_range? issue
    end

    expedited_issues.sort! { |a, b| a.key_as_i <=> b.key_as_i }

    data_sets = []
    expedited_issues.each do |issue|
      data_sets << make_expedite_lines_data_set(issue: issue)
    end

    render(binding, __FILE__)
  end

  def prepare_expedite_data issue
    expedite_start = nil
    result = []

    issue.changes.each do |change|
      next unless change.priority?

      # It's not enough for start and end points to be in the range. They might pass right through the visible area.
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

  def expedited_during_date_range? issue
    prepare_expedite_data(issue).any? do |time, action|
      next unless %i[expedite_start expedite_stop].include? action

      date_range.include? time.to_date
    end
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

  def make_expedite_lines_data_set issue:
    started_time = @cycletime.started_time(issue)
    stopped_time = @cycletime.stopped_time(issue)

    expedite_data = prepare_expedite_data issue
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

    last_change_time = expedite_data[-1][0].to_date
    if last_change_time && last_change_time <= date_range.end && stopped_time.nil?
      data << make_point(issue: issue, time: date_range.end, label: 'Still ongoing', expedited: expedited)
      dot_colors << 'blue' # It won't be visible so it doesn't matter
      point_styles << 'dash'
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
      segment: ExpeditedSegment.new
    }
  end
end
