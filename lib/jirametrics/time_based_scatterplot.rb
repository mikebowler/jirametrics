# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class TimeBasedScatterplot < ChartBase
  include GroupableIssueChart

  def initialize
    super

    @percentage_lines = []
    @highest_y_value = 0
  end

  def run
    items = all_items
    data_sets = create_datasets items
    overall_percent_line = calculate_percent_line(items)
    @percentage_lines << [overall_percent_line, CssVariable['--cycletime-scatterplot-overall-trendline-color']]

    return "<h1 class='foldable'>#{@header_text}</h1><div>No data matched the selected criteria. Nothing to show.</div>" if data_sets.empty?

    wrap_and_render(binding, __FILE__)
  end

  def create_datasets items
    data_sets = []

    group_issues(items).each do |rules, items_by_type|
      label = rules.label
      color = rules.color
      percent_line = calculate_percent_line items_by_type
      data = items_by_type.filter_map { |item| data_for_item(item, rules: rules) }
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

  def minimum_y_value
    nil
  end

  def data_for_item item, rules: nil
    y = y_value(item)
    min = minimum_y_value
    return nil if min && y < min

    @highest_y_value = y if @highest_y_value < y

    {
      y: y,
      x: chart_format(x_value(item)),
      title: [title_value(item, rules: rules)]
    }
  end

  def calculate_percent_line items
    min = minimum_y_value
    times = items.collect { |item| y_value(item) }
    times.reject! { |y| min && y < min }
    index = times.size * 85 / 100
    times.sort[index]
  end
end
