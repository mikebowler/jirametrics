# frozen_string_literal: true

require 'jirametrics/chart_base'

class ExpeditedChart < ChartBase
  EXPEDITED_SEGMENT = ChartBase.new.tap do |segment|
    def segment.to_json *_args
      expedited = CssVariable.new('--expedited-color').to_json
      not_expedited = CssVariable.new('--expedited-chart-no-longer-expedited').to_json

      <<~SNIPPET
        {
          borderColor: ctx => expedited(ctx, #{expedited}) || notExpedited(ctx, #{not_expedited}),
          borderDash: ctx => notExpedited(ctx, [6, 6])
        }
      SNIPPET
    end
  end

  attr_accessor :issues, :cycletime, :possible_statuses, :date_range
  attr_reader :expedited_label

  def initialize block
    super()

    header_text 'Expedited work'
    description_text <<-HTML
      <div class="p">
        This chart only shows issues that have been expedited at some point. We care about these as
        any form of expedited work will affect the entire system and will slow down non-expedited work.
        Refer to this article on
        <a href="https://improvingflow.com/2021/06/16/classes-of-service.html">classes of service</a>
        for a longer explanation on why we want to avoid expedited work.
      </div>
      <div class="p">
        The colour of the line indicates time that this issue was #{color_block '--expedited-color'} expedited
        or #{color_block '--expedited-chart-no-longer-expedited'} not expedited.
      </div>
      #{describe_non_working_days}
    HTML
    @x_axis_title = 'Date'
    @y_axis_title = 'Age in days'

    instance_eval(&block)
  end

  def run
    data_sets = find_expedited_issues.filter_map do |issue|
      make_expedite_lines_data_set(issue: issue, expedite_data: prepare_expedite_data(issue))
    end

    if data_sets.empty?
      '<h1 class="foldable">Expedited work</h1><div>There is no expedited work in this time period.</div>'
    else
      wrap_and_render(binding, __FILE__)
    end
  end

  def prepare_expedite_data issue
    expedite_start = nil
    result = []
    expedited_priority_names = issue.board.project_config.settings['expedited_priority_names']

    issue.changes.each do |change|
      next unless change.priority?

      if expedited_priority_names.include? change.value
        expedite_start = change.time.to_date
      elsif expedite_start
        if expedite_visible?(expedite_start, change.time.to_date)
          result << [expedite_start, :expedite_start]
          result << [change.time.to_date, :expedite_stop]
        end
        expedite_start = nil
      end
    end

    # If expedite_start is still set then we never ended.
    result << [expedite_start, :expedite_start] if expedite_start
    result
  end

  # True when an expedite span overlaps the chart's date range: either endpoint falls inside it, or it
  # starts before and ends after (spanning the whole range).
  def expedite_visible? start_date, stop_date
    date_range.include?(start_date) || date_range.include?(stop_date) ||
      (start_date < date_range.begin && stop_date > date_range.end)
  end

  def find_expedited_issues
    expedited_issues = @issues.reject do |issue|
      prepare_expedite_data(issue).empty?
    end

    expedited_issues.sort_by(&:key_as_i)
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
    started_date, stopped_date = issue.board.cycletime.started_stopped_dates(issue)

    expedite_data << [started_date, :issue_started] if started_date
    expedite_data << [stopped_date, :issue_stopped] if stopped_date
    expedite_data.sort_by!(&:first)

    # If none of the data would be visible on the chart then skip it.
    return nil unless expedite_data.any? { |time, _action| time.to_date >= date_range.begin }

    data = []
    dot_colors = []
    point_styles = []
    expedited = false

    expedite_data.each do |time, action|
      point, color, style, expedited = expedite_point(issue, time, action, expedited)
      data << point
      dot_colors << color
      point_styles << style
    end

    if still_ongoing?(expedite_data, stopped_date)
      data << make_point(issue: issue, time: date_range.end, label: 'Still ongoing', expedited: expedited)
      dot_colors << '' # It won't be visible so it doesn't matter
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
      segment: EXPEDITED_SEGMENT
    }
  end

  # Returns [point, dot_color, point_style, expedited] for one timeline event. The returned expedited
  # flag carries the (possibly changed) state forward to the next event.
  def expedite_point issue, time, action, expedited
    case action
    when :issue_started
      [make_point(issue: issue, time: time, label: 'Started', expedited: expedited),
       CssVariable['--expedited-chart-dot-issue-started-color'], 'rect', expedited]
    when :issue_stopped
      [make_point(issue: issue, time: time, label: 'Completed', expedited: expedited),
       CssVariable['--expedited-chart-dot-issue-stopped-color'], 'rect', expedited]
    when :expedite_start
      [make_point(issue: issue, time: time, label: 'Expedited', expedited: true),
       CssVariable['--expedited-chart-dot-expedite-started-color'], 'circle', true]
    when :expedite_stop
      [make_point(issue: issue, time: time, label: 'Not expedited', expedited: false),
       CssVariable['--expedited-chart-dot-expedite-stopped-color'], 'circle', false]
    else
      raise "Unexpected action: #{action}"
    end
  end

  # The issue is still expedited/open at the end of the chart: it hasn't stopped and its last recorded
  # change is on or before the end of the range.
  def still_ongoing? expedite_data, stopped_date
    return false if expedite_data.empty?

    last_change_time = expedite_data[-1][0].to_date
    last_change_time && last_change_time <= date_range.end && stopped_date.nil?
  end
end
