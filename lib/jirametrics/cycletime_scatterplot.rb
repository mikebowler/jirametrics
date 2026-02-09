# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class CycletimeScatterplot < ChartBase
  include GroupableIssueChart

  attr_accessor :possible_statuses

  def initialize block
    super()

    header_text 'Cycletime Scatterplot'
    description_text <<-HTML
      <div class="p">
        This chart shows only completed work and indicates both what day it completed as well as
        how many days it took to get done. Hovering over a dot will show you the ID of the work item.
      </div>
      <div class="p">
        The #{color_block '--cycletime-scatterplot-overall-trendline-color'} line indicates the 85th
        percentile (<%= overall_percent_line %> days). 85% of all
        items on this chart fall on or below the line and the remaining 15% are above the line. 85%
        is a reasonable proxy for "most" so that we can say that based on this data set, we can
        predict that most work of this type will complete in <%= overall_percent_line %> days or
        less. The other lines reflect the 85% line for that respective type of work.
      </div>
      #{describe_non_working_days}
    HTML

    init_configuration_block block do
      grouping_rules do |issue, rule|
        rule.label = issue.type
        rule.color = color_for type: issue.type
      end
    end

    @percentage_lines = []
    @highest_y_value = 0
  end

  def all_items
    completed_issues_in_range include_unstarted: false
  end

  def x_value item
    item.board.cycletime.started_stopped_times(item).last
  end

  def y_value item
    item.board.cycletime.cycletime(item)
  end

  def title_value item
    "#{item.key} : #{item.summary} (#{label_days(y_value(item))})"
  end

  def y_axis_heading
    'Cycle time in days'
  end

  def run
    items = all_items
    data_sets = create_datasets items
    overall_percent_line = calculate_percent_line(items)
    @percentage_lines << [overall_percent_line, CssVariable['--cycletime-scatterplot-overall-trendline-color']]

    return "<h1>#{@header_text}</h1>No data matched the selected criteria. Nothing to show." if data_sets.empty?

    wrap_and_render(binding, __FILE__)
  end

  def create_datasets items
    data_sets = []

    group_issues(items).each do |rules, completed_items_by_type|
      label = rules.label
      color = rules.color
      percent_line = calculate_percent_line completed_items_by_type
      data = completed_items_by_type.filter_map { |issue| data_for_issue(issue) }
      data_sets << {
        label: "#{label} (85% at #{label_days(percent_line)})",
        data: data,
        fill: false,
        showLine: false,
        backgroundColor: color
      }

      data_sets << trend_line_data_set(label: label, data: data, color: color)

      @percentage_lines << [percent_line, color]
    end
    data_sets
  end

  def show_trend_lines
    @show_trend_lines = true
  end

  def trend_line_data_set label:, data:, color:
    points = data.collect do |hash|
      [Time.parse(hash[:x]).to_i, hash[:y]]
    end

    # The trend calculation works with numbers only so convert Time to an int and back
    calculator = TrendLineCalculator.new(points)
    data_points = calculator.chart_datapoints(
      range: time_range.begin.to_i..time_range.end.to_i,
      max_y: @highest_y_value
    )
    data_points.each do |point_hash|
      point_hash[:x] = chart_format Time.at(point_hash[:x])
    end

    {
      type: 'line',
      label: "#{label} Trendline",
      data: data_points,
      fill: false,
      borderWidth: 1,
      markerType: 'none',
      borderColor: color,
      borderDash: [6, 3],
      pointStyle: 'dash',
      hidden: !@show_trend_lines
    }
  end

  def data_for_issue item
    cycle_time = y_value(item)
    return nil if cycle_time < 1 # These will get called out on the quality report

    @highest_y_value = cycle_time if @highest_y_value < cycle_time

    {
      y: cycle_time,
      x: chart_format(x_value(item)),
      title: [title_value(item)]
    }
  end

  def calculate_percent_line items
    times = items.collect { |item| y_value(item) }
    index = times.size * 85 / 100
    times.sort[index]
  end
end
