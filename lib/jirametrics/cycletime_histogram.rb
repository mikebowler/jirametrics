# frozen_string_literal: true

require 'jirametrics/time_based_histogram'

class CycletimeHistogram < TimeBasedHistogram
  attr_accessor :possible_statuses

  def initialize block
    super()

    @x_axis_title = 'Cycletime in days'
    @y_axis_title = 'Count'

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

  def all_items
    stopped_issues = completed_issues_in_range include_unstarted: true

    # For the histogram, we only want to consider items that have both a start and a stop time.
    stopped_issues.select { |issue| issue.board.cycletime.started_stopped_times(issue).first }
  end

  def value_for_item issue
    issue.board.cycletime.cycletime(issue)
  end

  def title_for_item count:, value:
    "#{count} items completed in #{label_days value}"
  end

  def sort_items items
    items.sort_by(&:key_as_i)
  end

  def label_for_item issue, hint:
    "#{issue.key} : #{issue.summary}#{" #{hint}" if hint}"
  end
end
