# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class TimeBasedHistogram < ChartBase
  include GroupableIssueChart

  attr_reader :show_stats

  def initialize
    super

    percentiles [50, 85, 98]
    @show_stats = true
  end

  def percentiles percs = nil
    @percentiles = percs unless percs.nil?
    @percentiles
  end

  def disable_stats
    @show_stats = false
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

    # Calculate the average
    weighted_sum = histogram_data.reduce(0) { |sum, (value, frequency)| sum + (value * frequency) }
    average = total_values.zero? ? 0 : weighted_sum.to_f / total_values

    # Find the mode (or modes!) and the spread of the distribution
    sorted_histogram = histogram_data.sort_by { |_value, frequency| frequency }
    max_freq = sorted_histogram[-1][1]
    mode = sorted_histogram.select { |_v, f| f == max_freq }

    minmax = histogram_data.keys.minmax

    # Calculate percentiles
    sorted_values = histogram_data.keys.sort
    cumulative_counts = {}
    cumulative_sum = 0

    sorted_values.each do |value|
      cumulative_sum += histogram_data[value]
      cumulative_counts[value] = cumulative_sum
    end

    percentile_results = {}
    percentiles.each do |percentile|
      rank = (percentile / 100.0) * total_values
      percentile_value = sorted_values.find { |value| cumulative_counts[value] >= rank }
      percentile_results[percentile] = percentile_value
    end

    {
      average: average,
      mode: mode.collect(&:first).sort,
      min: minmax[0],
      max: minmax[1],
      percentiles: percentile_results
    }
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
