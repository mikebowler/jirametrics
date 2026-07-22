# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class PullRequestCycleTimeHistogram < TimeBasedHistogram
  def initialize block
    super()

    @x_axis_title = 'Cycle time in days'

    header_text 'PR Histogram'
    description_text <<-HTML
      <div class="p">
        This cycletime Histogram shows how many pull requests completed in a certain timeframe. This can be
        useful for determining how many different types of work are flowing through, based on the
        lengths of time they take.
      </div>
    HTML

    init_configuration_block(block) do
      grouping_rules do |pull_request, rule|
        rule.label = pull_request.repo
      end
    end
  end

  def all_items
    result = []
    issues.each do |issue|
      next unless issue.github_prs

      issue.github_prs.each do |pr|
        next unless pr.closed_at

        result << pr
      end
    end
    result.uniq
  end

  def value_for_item item
    duration_in_unit item.opened_at, item.closed_at
  end

  def title_for_item count:, value:
    "#{count} PR#{'s' unless count == 1} closed in #{label_cycletime value}"
  end

  def sort_items items
    items.sort_by(&:opened_at)
  end

  def label_for_item item, hint:
    label = "#{item.number} #{item.title}"
    label << hint if hint
    label
  end
end
