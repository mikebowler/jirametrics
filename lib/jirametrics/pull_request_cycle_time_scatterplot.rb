# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class PullRequestCycleTimeScatterplot < TimeBasedScatterplot
  def initialize block
    super()

    @y_axis_title = 'Cycle time in days'

    header_text 'Pull Request (PR) Scatterplot'
    description_text <<-HTML
      <div class="p">
        This graph shows the cycle time for all closed pull requests (time from opened to closed).
      </div>
      #{describe_non_working_days}
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
    duration_in_unit pull_request.opened_at, pull_request.closed_at
  end

  def title_value pull_request, rules: nil
    age_label = label_cycletime y_value(pull_request)
    keys = pull_request.issue_keys.join(', ')
    "#{keys} | #{pull_request.title} | #{rules.label} | Age:#{age_label}#{lines_changed_text(pull_request)}"
  end

  def lines_changed_text pull_request
    return '' unless pull_request.changed_files

    summary = additions_deletions_summary pull_request
    " | Lines changed: [#{summary}], Files changed: #{to_human_readable pull_request.changed_files}"
  end

  # The "+10 -4" bit: each side only appears when non-zero, joined by a space only when both do.
  def additions_deletions_summary pull_request
    additions = pull_request.additions || 0
    deletions = pull_request.deletions || 0
    parts = []
    parts << "+#{to_human_readable additions}" unless additions.zero?
    parts << "-#{to_human_readable deletions}" unless deletions.zero?
    parts.join(' ')
  end
end
