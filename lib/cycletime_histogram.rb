# frozen_string_literal: true

require './lib/groupable_issue_chart'

class CycletimeHistogram < ChartBase
  include GroupableIssueChart
  attr_accessor :possible_statuses

  def initialize block = nil
    super()

    header_text 'Cycletime Histogram'
    description_text <<-HTML
      <p>
        The Cycletime Histogram shows how many items completed in a certain timeframe. This can be
        useful for determining how many different types of work are flowing through, based on the
        lengths of time they take.
      </p>
    HTML
    check_data_quality_for(
      :status_changes_after_done,
      :completed_but_not_started,
      :backwords_through_statuses,
      :backwards_through_status_categories,
      :created_in_wrong_status,
      :status_not_on_board,
      :stopped_before_started
    )

    init_configuration_block(block) do
      grouping_rules do |issue, rule|
        rule.label = issue.type
        rule.color = color_for type: issue.type
      end
    end
  end

  def run
    stopped_issues = completed_issues_in_range include_unstarted: true

    # For data quality, we need to look at everything that's stopped
    data_quality = scan_data_quality(stopped_issues)

    # For the histogram, we only want to consider items that have both a start and a stop time.
    histogram_issues = stopped_issues.select { |issue| @cycletime.started_time(issue) }
    rules_to_issues = group_issues histogram_issues

    data_sets = rules_to_issues.keys.collect do |rules|
      data_set_for(
        histogram_data: histogram_data_for(issues: rules_to_issues[rules]),
        label: rules.label,
        color: rules.color
      )
    end

    wrap_and_render(binding, __FILE__)
  end

  def histogram_data_for issues:
    count_hash = {}
    issues.each do |issue|
      days = @cycletime.cycletime(issue)
      count_hash[days] = (count_hash[days] || 0) + 1
    end
    count_hash
  end

  def data_set_for histogram_data:, label:, color:
    keys = histogram_data.keys.sort
    {
      type: 'bar',
      label: label,
      data: keys.sort.collect do |key|
        next if histogram_data[key].zero?

        {
          x: key,
          y: histogram_data[key],
          title: "#{histogram_data[key]} items completed in #{label_days key}"
        }
      end.compact,
      backgroundColor: color,
      borderRadius: 0
    }
  end
end
