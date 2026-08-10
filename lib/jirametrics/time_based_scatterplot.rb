# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'
require 'jirametrics/time_based_chart'

class TimeBasedScatterplot < TimeBasedChart
  include GroupableIssueChart

  attr_reader :y_axis_cap_percentile, :percentage_lines

  def initialize
    super

    @percentage_lines = []
    @highest_y_value = 0
    @percentiles = [85]
  end

  # On a scatterplot the cycle time is plotted up the y-axis.
  def value_axis_title= title
    @y_axis_title = title
  end

  def cap_y_axis percentile: 98
    @y_axis_cap_percentile = percentile
  end

  # Percentile reference lines. The chart level value defines the lines drawn across the whole
  # data set AND the default for each group; a group can override with rule.percentiles.
  # An empty list switches the lines off.
  def percentiles list = nil
    @percentiles = validate_percentiles(list) unless list.nil?
    @percentiles
  end

  def run
    items = all_items
    data_sets = create_datasets items
    overall_color = CssVariable['--cycletime-scatterplot-overall-trendline-color']

    percentile_lines_for(items, @percentiles).each do |percentile, value|
      @percentage_lines << {
        percentile: percentile, value: value, color: overall_color,
        id: "overall_#{percentile}", group_label: nil
      }
    end

    if data_sets.empty?
      return "<h1 class='foldable'>#{@header_text}</h1>" \
        '<div>No data matched the selected criteria. Nothing to show.</div>'
    end

    wrap_and_render(binding, __FILE__)
  end

  def create_datasets items
    @cap = compute_cap items
    data_sets = []

    group_issues(items).each_with_index do |(rules, items_by_type), group_index|
      label = rules.label
      color = rules.color
      lines = percentile_lines_for items_by_type, (rules.percentiles || @percentiles)
      data = items_by_type.filter_map { |item| data_for_item(item, rules: rules) }
      data_sets << {
        label: percentile_label(label, lines),
        data: data,
        fill: false,
        showLine: false,
        backgroundColor: color
      }

      data_sets << trend_line_data_set(label: label, data: data, color: color)

      lines.each do |percentile, value|
        @percentage_lines << {
          percentile: percentile, value: value, color: color,
          id: "group#{group_index}_#{percentile}", group_label: label
        }
      end
    end
    data_sets
  end

  # "Story (85% at 81 days)" for one, comma separated for several, bare label for none.
  def percentile_label label, lines
    return label if lines.empty?

    parts = lines.collect { |percentile, value| "#{percentile}% at #{label_days value}" }
    "#{label} (#{parts.join ', '})"
  end

  def show_trend_lines
    @show_trend_lines = true
  end

  # Group label to the annotation ids belonging to that group, so the legend handler can toggle
  # all of a group's lines. Overall lines are deliberately absent; they are not owned by any
  # group and stay visible when a group is switched off.
  def legend_annotation_map
    @percentage_lines.reject { |line| line[:group_label].nil? }
      .group_by { |line| line[:group_label] }
      .transform_values { |lines| lines.collect { |line| line[:id] } }
  end

  def trend_line_data_set label:, data:, color:
    points = data.collect do |hash|
      [Time.parse(hash[:x]).to_i, hash[:true_y] || hash[:y]]
    end

    # The trend calculation works with numbers only so convert Time to an int and back
    calculator = TrendLineCalculator.new(points)
    data_points = calculator.chart_datapoints(
      range: time_range.begin.to_i..time_range.end.to_i,
      max_y: (@cap ? @cap[:cutoff] : @highest_y_value)
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

    over = @cap && y > @cap[:cutoff]
    plotted_y = over ? @cap[:pin_row] : y
    @highest_y_value = plotted_y if @highest_y_value < plotted_y

    point = {
      y: plotted_y,
      x: chart_format(x_value(item)),
      title: [title_value(item, rules: rules)]
    }
    if over
      point[:over] = true
      point[:true_y] = y
    end
    point
  end

  # Returns [[percentile, value], ...] for the requested percentiles, sorted ascending by
  # percentile and dropping any that have no value because the item list is empty after
  # filtering. Sorting happens here, not in the caller, because GroupingRules#percentiles is
  # user-assigned with no ordering guarantee.
  def percentile_lines_for items, percentiles
    percentiles.sort.filter_map do |percentile|
      value = percentile_value items, percentile
      [percentile, value] unless value.nil?
    end
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
      outlier_count: outlier_count,
      label: cap_label(outlier_count: outlier_count, cutoff: cutoff)
    }
  end

  private

  def cap_label outlier_count:, cutoff:
    item_word = outlier_count == 1 ? 'item' : 'items'
    "#{outlier_count} #{item_word} above #{cutoff.round} days"
  end

  def filtered_values items
    min = minimum_y_value
    values = items.collect { |item| y_value(item) }
    values.reject! { |value| min && value < min }
    values
  end

  def validate_percentiles list
    list.each do |percentile|
      raise ArgumentError, "percentile #{percentile} must be an integer" unless percentile.is_a? Integer

      raise ArgumentError, "percentile #{percentile} must be between 0 and 100" unless percentile.between?(0, 100)
    end
    list.uniq.sort
  end
end
