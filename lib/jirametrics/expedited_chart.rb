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

    instance_eval(&block)
  end

  def run
    data_sets = find_expedited_issues.filter_map do |issue|
      make_expedite_lines_data_set(issue: issue, expedite_data: prepare_expedite_data(issue))
    end

    if data_sets.empty?
      '<h1>Expedited work</h1>There is no expedited work in this time period.'
    else
      wrap_and_render(binding, __FILE__)
    end
  end

  def prepare_expedite_data issue
    expedite_start = nil
    result = []
    expedited_priority_names = issue.board.expedited_priority_names

    issue.changes.each do |change|
      next unless change.priority?

      if expedited_priority_names.include? change.value
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
    cycletime = issue.board.cycletime
    started_time = cycletime.started_time(issue)
    stopped_time = cycletime.stopped_time(issue)

    expedite_data << [started_time, :issue_started] if started_time
    expedite_data << [stopped_time, :issue_stopped] if stopped_time
    expedite_data.sort_by! { |a| a[0] }

    # If none of the data would be visible on the chart then skip it.
    return nil unless expedite_data.any? { |time, _action| time.to_date >= date_range.begin }

    data = []
    dot_colors = []
    point_styles = []
    expedited = false

    expedite_data.each do |time, action|
      case action
      when :issue_started
        data << make_point(issue: issue, time: time, label: 'Started', expedited: expedited)
        dot_colors << CssVariable['--expedited-chart-dot-issue-started-color']
        point_styles << 'rect'
      when :issue_stopped
        data << make_point(issue: issue, time: time, label: 'Completed', expedited: expedited)
        dot_colors << CssVariable['--expedited-chart-dot-issue-stopped-color']
        point_styles << 'rect'
      when :expedite_start
        data << make_point(issue: issue, time: time, label: 'Expedited', expedited: true)
        dot_colors << CssVariable['--expedited-chart-dot-expedite-started-color']
        point_styles << 'circle'
        expedited = true
      when :expedite_stop
        data << make_point(issue: issue, time: time, label: 'Not expedited', expedited: false)
        dot_colors << CssVariable['--expedited-chart-dot-expedite-stopped-color']
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
        dot_colors << '' # It won't be visible so it doesn't matter
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
