# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'
require 'jirametrics/time_based_chart'

class TimeBasedScatterplot < TimeBasedChart
  include GroupableIssueChart

  attr_reader :y_axis_cap_percentile

  def initialize
    super

    @percentage_lines = []
    @highest_y_value = 0
  end

  # On a scatterplot the cycle time is plotted up the y-axis.
  def value_axis_title= title
    @y_axis_title = title
  end

  def cap_y_axis percentile: 98
    @y_axis_cap_percentile = percentile
  end

  def run
    items = all_items
    data_sets = create_datasets items
    overall_percent_line = calculate_percent_line(items)
    @percentage_lines << [overall_percent_line, CssVariable['--cycletime-scatterplot-overall-trendline-color']]

    if data_sets.empty?
      return "<h1 class='foldable'>#{@header_text}</h1>" \
        '<div>No data matched the selected criteria. Nothing to show.</div>'
    end

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
    percentile_value items, 85
  end

  def percentile_value items, percentile
    values = filtered_values(items)
    return nil if values.empty?

    index = [values.size * percentile / 100, values.size - 1].min
    values.sort[index]
  end

  def compute_cap items
    return nil unless @y_axis_cap_percentile

    cutoff = percentile_value items, @y_axis_cap_percentile
    return nil unless cutoff

    values = filtered_values(items)
    outlier_count = values.count { |value| value > cutoff }
    return nil if outlier_count.zero?

    pad = cutoff * 0.06        # breathing room so the top real dot does not touch the break
    gutter_height = cutoff * 0.15
    sep = cutoff + pad
    {
      cutoff: cutoff,
      sep: sep,
      pin_row: sep + (gutter_height * 0.55),
      axis_max: (sep + gutter_height).ceil,
      outlier_count: outlier_count
    }
  end

  private

  def filtered_values items
    min = minimum_y_value
    values = items.collect { |item| y_value(item) }
    values.reject! { |value| min && value < min }
    values
  end
end
