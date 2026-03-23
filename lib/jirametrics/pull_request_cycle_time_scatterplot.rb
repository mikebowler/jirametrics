# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class PullRequestCycleTimeScatterplot < TimeBasedScatterplot
  def initialize block
    super()

    @cycletime_unit = :days
    @y_axis_title = 'Cycle time in days'

    header_text 'Pull Request (PR) Scatterplot'
    description_text <<-HTML
      <div class="p">
        This graph shows the cycle time for all closed pull requests (time from opened to closed).
      </div>
      #{describe_non_working_days}
    HTML

    init_configuration_block(block) do
      grouping_rules do |pull_request, _rule|
        rules.label = pull_request.repo
      end
    end
  end

  def cycletime_unit unit
    unless %i[minutes hours days].include?(unit)
      raise ArgumentError, "cycletime_unit must be :minutes, :hours, or :days, got #{unit.inspect}"
    end

    @cycletime_unit = unit
    @y_axis_title = "Cycle time in #{unit}"
  end

  def all_items
    result = []
    issues.each do |issue|
      issue.github_prs&.each do |pr|
        result << pr if pr.closed_at
      end
    end
    result
  end

  def x_value pull_request
    pull_request.closed_at
  end

  def y_value pull_request
    divisor = { minutes: 60, hours: 3600, days: 86_400 }[@cycletime_unit]
    ((pull_request.closed_at - pull_request.opened_at) / divisor).round
  end

  def label_cycletime value
    case @cycletime_unit
    when :minutes then label_minutes(value)
    when :hours then label_hours(value)
    when :days then label_days(value)
    end
  end

  def title_value pull_request, rules: nil
    age_label = label_cycletime y_value(pull_request)
    "#{pull_request.title} | #{rules.label} | Age:#{age_label}#{lines_changed_text(pull_request)}"
  end

  def lines_changed_text pull_request
    return '' unless pull_request.changed_files

    additions = pull_request.additions || 0
    deletions = pull_request.deletions || 0
    text = +' | Lines changed: ['
    text << "+#{to_human_readable additions}" unless additions.zero?
    text << ' ' if additions != 0 && deletions != 0
    text << "-#{to_human_readable deletions}" unless deletions.zero?
    text << "], Files changed: #{to_human_readable pull_request.changed_files}"
    text
  end
end
