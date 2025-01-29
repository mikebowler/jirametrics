
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

    the_stats = {}

    data_sets = rules_to_issues.keys.collect do |rules|
      the_issue_type = rules.label
      the_histogram = histogram_data_for(issues: rules_to_issues[rules])
      the_stats[the_issue_type] = stats_for histogram_data:the_histogram, percentiles:[50, 85, 95]

      data_set_for(
        histogram_data: the_histogram,
        label: the_issue_type,
        color: rules.color
      )
    end

    return "<h1>#{@header_text}</h1>No data matched the selected criteria. Nothing to show." if data_sets.empty?

    wrap_and_render(binding, __FILE__) << render_stats(the_stats)
  end

  def render_stats(stats)
    result = <<~HTML
      <p>STATS</p>
      <div>
       <table class="standard">
        <tr>
          <th>Issue Type</th>
          <th>Avg</th>
          <th>Mode</th>
          <th>50th</th>
          <th>85th</th>
          <th>95th</th>
        </tr>
    HTML

    stats.each do |k, v|
      result << <<~HTML
        <tr>
          <td>#{k}</td>
          <td>#{sprintf('%.2f', v[:average])}</td>
          <td>#{v[:mode]}</td>
          <td>#{v[:percentiles][50]}</td>
          <td>#{v[:percentiles][85]}</td>
          <td>#{v[:percentiles][95]}</td>
        </tr>
      HTML
    end

    result << <<~HTML
      </table>
      </div>
    HTML

    result
  end

  def histogram_data_for issues:
    count_hash = {}
    issues.each do |issue|
      days = issue.board.cycletime.cycletime(issue)
      count_hash[days] = (count_hash[days] || 0) + 1 if days.positive?
    end
    count_hash
  end

  def stats_for histogram_data:, percentiles:[]
    return {} if histogram_data.empty?

    total_values = histogram_data.values.sum

    # Calculate the average
    weighted_sum = histogram_data.reduce(0) { |sum, (value, frequency)| sum + value * frequency }
    average = total_values != 0? weighted_sum.to_f / total_values : 0

     # Find the mode (or modes!)
    sorted_histogram = histogram_data.sort_by{ |value, frequency| frequency }
    max_freq = sorted_histogram[-1][1]
    mode = sorted_histogram.select { |v,f| f == max_freq }

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
      mode: mode.length == 1? mode[0][0] : mode.collect{|x| x[0] }.sort,
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
