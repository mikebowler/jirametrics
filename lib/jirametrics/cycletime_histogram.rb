# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class CycletimeHistogram < ChartBase
  include GroupableIssueChart
  attr_accessor :possible_statuses

  def initialize block
    super()

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

  def run
    stopped_issues = completed_issues_in_range include_unstarted: true

    # For the histogram, we only want to consider items that have both a start and a stop time.
    histogram_issues = stopped_issues.select { |issue| issue.board.cycletime.started_stopped_times(issue).first }
    rules_to_issues = group_issues histogram_issues

    data_sets = rules_to_issues.keys.collect do |rules|
      data_set_for(
        histogram_data: histogram_data_for(issues: rules_to_issues[rules]),
        label: rules.label,
        color: rules.color
      )
    end

    return "<h1>#{@header_text}</h1>No data matched the selected criteria. Nothing to show." if data_sets.empty?

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

  def stats_for histogram_data:
    return {} if histogram_data.empty?

    total_values = histogram_data.values.sum

    # Calculate the average
    weighted_sum = histogram_data.reduce(0) { |sum, (value, frequency)| sum + value * frequency }
    average = total_values != 0? weighted_sum.to_f / total_values : 0

    { average: average } 
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
