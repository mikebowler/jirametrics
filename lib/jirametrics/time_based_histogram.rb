# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'
require 'jirametrics/percentile_validation'
require 'jirametrics/time_based_chart'

class TimeBasedHistogram < TimeBasedChart
  include GroupableIssueChart
  include PercentileValidation

  attr_reader :show_stats

  def initialize
    super

    percentiles [50, 85, 98]
    @show_stats = true
  end

  # On a histogram the cycle time is plotted along the x-axis (count is on the y-axis).
  def value_axis_title= title
    @x_axis_title = title
  end

  # Which percentiles to show as columns in the statistics table. An empty list drops the columns
  # entirely. Values are validated here rather than at use, because they feed the percentile
  # arithmetic and the table headers, where a bad one produces a wrong chart instead of an error.
  def percentiles list = nil
    @percentiles = validate_percentiles(list) unless list.nil?
    @percentiles
  end

  def disable_stats
    @show_stats = false
  end

  # What a given percentile is actually good for. These used to be a hardcoded list describing
  # the 50th, 85th and 98th, sitting underneath a table whose columns follow the configuration,
  # so the two drifted apart the moment anyone changed the setting. Bands rather than exact
  # values, because 90 deserves an answer just as much as 85 does.
  def percentile_explanation percentile
    case percentile
    when 0..49
      'below the median, so half or more of your work takes longer than this. Useful for ' \
        'understanding your faster cases, but not a number to plan around.'
    when 50
      'also known as the <b>Median</b>. Useful to establish short feedback loops, to monitor ' \
        "that it's not drifting to the right."
    when 51..94
      'useful to establish service level expectations, accounting for rare events.'
    else
      'useful to gauge worst case expectations.'
    end
  end

  def run
    histogram_items = all_items
    rules_to_items = group_issues histogram_items

    the_stats = {}

    overall_histogram = histogram_data_for(items: histogram_items).transform_values(&:size)
    the_stats[:all] = stats_for histogram_data: overall_histogram, percentiles: @percentiles
    data_sets = rules_to_items.keys.collect do |rules|
      the_label = rules.label
      the_histogram = histogram_data_for(items: rules_to_items[rules])
      if @show_stats
        the_stats[the_label] = stats_for(
          histogram_data: the_histogram.transform_values(&:size), percentiles: @percentiles
        )
      end

      data_set_for(
        histogram_data: the_histogram,
        label: the_label,
        color: rules.color
      )
    end

    if data_sets.empty?
      return "<h1 class='foldable'>#{@header_text}</h1>" \
             '<div>No data matched the selected criteria. Nothing to show.</div>'
    end

    wrap_and_render(binding, __FILE__)
  end

  def histogram_data_for items:
    items_hash = {}
    items.each do |item|
      days = value_for_item item
      (items_hash[days] ||= []) << item if days.positive?
    end
    items_hash
  end

  def stats_for histogram_data:, percentiles:
    return {} if histogram_data.empty?

    total_values = histogram_data.values.sum
    min, max = histogram_data.keys.minmax
    {
      average: average_for(histogram_data, total_values),
      mode: modes_for(histogram_data),
      min: min,
      max: max,
      percentiles: percentiles_for(histogram_data, percentiles, total_values)
    }
  end

  def average_for histogram_data, total_values
    return 0 if total_values.zero?

    weighted_sum = histogram_data.reduce(0) { |sum, (value, frequency)| sum + (value * frequency) }
    weighted_sum.to_f / total_values
  end

  # Every value that ties for the highest frequency, so a flat or multi-modal distribution returns them all.
  def modes_for histogram_data
    sorted_by_frequency = histogram_data.sort_by { |_value, frequency| frequency }
    max_frequency = sorted_by_frequency[-1][1]
    sorted_by_frequency.select { |_value, frequency| frequency == max_frequency }.collect(&:first).sort
  end

  # The data arrives as value => count. Expanded back to a flat list so that the one shared
  # percentile implementation is used here too: this chart and the scatterplot must not report
  # different answers for the same percentile of the same data. Chart sized data makes the
  # expansion cheap.
  def percentiles_for histogram_data, percentiles, _total_values
    values = histogram_data.flat_map { |value, count| Array.new(count, value) }
    percentiles.to_h { |percentile| [percentile, percentile_of(values, percentile)] }
  end

  def sort_items items
    items
  end

  def label_for_item item, hint:
    raise NotImplementedError, "#{self.class} must implement label_for_item"
  end

  def data_set_for histogram_data:, label:, color:
    {
      type: 'bar',
      label: label,
      data: histogram_data.keys.sort.filter_map do |days|
        items = histogram_data[days]
        next if items.empty?

        {
          x: days,
          y: items.size,
          title: [title_for_item(count: items.size, value: days)] +
            sort_items(items).collect do |item|
              hint = @issue_hints&.fetch(item, nil)
              label_for_item(item, hint: hint)
            end
        }
      end,
      backgroundColor: color,
      borderRadius: 0
    }
  end
end
