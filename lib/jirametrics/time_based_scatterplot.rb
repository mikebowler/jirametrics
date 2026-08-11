# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'
require 'jirametrics/percentile_validation'
require 'jirametrics/time_based_chart'

class TimeBasedScatterplot < TimeBasedChart
  include GroupableIssueChart

  # What the whole-data-set percentile lines call themselves when you hover them. They have no
  # legend entry, so without this there is nothing identifying them at all. "items" rather than
  # "data" or "everything" because it matches the description prose and because anything a
  # grouping rule ignored has already been dropped by the time these lines are calculated.
  OVERALL_LABEL = 'All items'
  include PercentileValidation

  # percentage_lines is internal, not part of the documented config DSL. It exists so that specs
  # and the ERB can see the computed lines without reaching into instance variables. Its shape,
  # including the :id strings that encode positional group indices, is free to change.
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
        id: "overall_#{percentile}", dataset_index: nil, label: OVERALL_LABEL
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

      # Where this group's scatter set is about to land. The legend handler knows the clicked
      # dataset by index, so that's what the annotation map is keyed by.
      dataset_index = data_sets.size
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
          id: "group#{group_index}_#{percentile}", dataset_index: dataset_index, label: label
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

  # The lines are always built but drawn hidden unless asked for, so this stays empty until they
  # are actually switched on. Note the caller must be the ERB tag <%= trend_line_description %>:
  # description_text is built during initialize, before the config block has called
  # show_trend_lines, so interpolation would freeze "off" in permanently.
  def trend_line_description
    return '' unless @show_trend_lines

    <<-HTML
      <div class="p">
        The dashed lines are trend lines, one per group in that group's colour. Each is a straight
        line fitted through that group's dots, so the slope tells you whether cycle times have been
        getting longer or shorter across the period shown. A line sloping up means work of that
        kind has been taking progressively longer to finish.
      </div>
      <div class="p">
        Read the slope as a description of this window rather than a prediction. A line is drawn
        whenever a group has at least three dots and nothing checks how well it actually fits
        them, so a scattered cloud with no real trend in it still gets a confident looking line.
        It is a straight line, so it cannot show a trend that changed direction partway through,
        and a handful of unusually long items will tilt it noticeably. If the slope surprises you,
        look at the dots before you believe it.
      </div>
    HTML
  end

  # Dataset index to the annotation ids belonging to that dataset's group, so the legend handler
  # can toggle all of a group's lines. Keyed by index rather than by label because two groups may
  # legitimately share a label while differing in colour, and keying by label would then toggle
  # both of them at once. Overall lines are deliberately absent; they are not owned by any group
  # and stay visible when a group is switched off.
  def legend_annotation_map
    @percentage_lines.reject { |line| line[:dataset_index].nil? }
      .group_by { |line| line[:dataset_index] }
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
end
