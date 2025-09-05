# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class CycletimeHistogram < ChartBase
  include GroupableIssueChart
  attr_accessor :possible_statuses
  attr_reader :show_stats

  def initialize block
    super()

    percentiles [50, 85, 98]
    @show_stats = true

    header_text 'Cycletime Histogram'
    description_text <<-HTML
      <p>
        The Cycletime Histogram shows how many items completed in a certain timeframe. This can be
        useful for determining how many different types of work are flowing through, based on the
        lengths of time they take.
      </p>
    HTML

    init_configuration_block(block) do
      grouping_rules do |issue, rule|
        rule.label = issue.type
        rule.color = color_for type: issue.type
      end
    end
  end

  def percentiles percs = nil
    @percentiles = percs unless percs.nil?
    @percentiles
  end

  def disable_stats
    @show_stats = false
  end

  def run
    stopped_issues = completed_issues_in_range include_unstarted: true

    # For the histogram, we only want to consider items that have both a start and a stop time.
    histogram_issues = stopped_issues.select { |issue| issue.board.cycletime.started_stopped_times(issue).first }
    rules_to_issues = group_issues histogram_issues

    the_stats = {}

    overall_stats = stats_for histogram_data: histogram_data_for(issues: histogram_issues), percentiles: @percentiles
    the_stats[:all] = overall_stats
    data_sets = rules_to_issues.keys.collect do |rules|
      the_issue_type = rules.label
      the_histogram = histogram_data_for(issues: rules_to_issues[rules])
      the_stats[the_issue_type] = stats_for histogram_data: the_histogram, percentiles: @percentiles if @show_stats

      data_set_for(
        histogram_data: the_histogram,
        label: the_issue_type,
        color: rules.color
      )
    end

    if data_sets.empty?
      return "<h1 class='foldable'>#{@header_text}</h1><div>No data matched the selected criteria. Nothing to show.</div>"
    end

    wrap_and_render(binding, __FILE__)
  end

  def histogram_data_for issues:
    count_hash = {}
    issues.each do |issue|
      days = issue.board.cycletime.cycletime(issue)
      count_hash[days] = (count_hash[days] || 0) + 1 if days.positive?
    end
    count_hash
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

  def data_set_for histogram_data:, label:, color:
    keys = histogram_data.keys.sort
    {
      type: 'bar',
      label: label,
      data: keys.sort.filter_map do |key|
        next if histogram_data[key].zero?

        {
          x: key,
          y: histogram_data[key],
          title: "#{histogram_data[key]} items completed in #{label_days key}"
        }
      end,
      backgroundColor: color,
      borderRadius: 0
    }
  end
end
