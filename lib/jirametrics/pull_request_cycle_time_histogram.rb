# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class PullRequestCycleTimeHistogram < TimeBasedHistogram
  def initialize block
    super()

    @cycletime_unit = :days
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
        rules.label = pull_request.repo
      end
    end
  end

  def cycletime_unit unit
    unless %i[minutes hours days].include?(unit)
      raise ArgumentError, "cycletime_unit must be :minutes, :hours, or :days, got #{unit.inspect}"
    end

    @cycletime_unit = unit
    @x_axis_title = "Cycle time in #{unit}"
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
    divisor = { minutes: 60.0, hours: 3600.0, days: 86_400.0 }[@cycletime_unit]
    ((item.closed_at - item.opened_at) / divisor).ceil
  end

  def label_cycletime value
    case @cycletime_unit
    when :minutes then label_minutes(value)
    when :hours then label_hours(value)
    when :days then label_days(value)
    end
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
