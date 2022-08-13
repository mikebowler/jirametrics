# frozen_string_literal: true

require './lib/chart_base'
require './lib/groupable_issue_chart'

class AgingWorkInProgressChart < ChartBase
  include GroupableIssueChart
  attr_accessor :possible_statuses

  def initialize block = nil
    super()
    header_text 'Aging Work in Progress'
    description_text <<-HTML
      <p>
        This chart shows only work items that have started but not completed, grouped by the column
      they're currently in. Hovering over a dot will show you the ID of that work item.
      </p>
      <p>
        The gray area indicates the 85% mark for work items that have passed through here - 85% of
        previous work items left this column while still inside the gray area. Any work items above
        the gray area are outliers and they are the items that you should pay special attention to.
      </p>
    HTML
    check_data_quality_for(
      :status_changes_after_done,
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

  def board_columns
    current_board.visible_columns
  end

  def run
    data_sets = make_data_sets
    column_headings = board_columns.collect(&:name)

    data_quality = scan_data_quality @issues

    wrap_and_render(binding, __FILE__)
  end

  def make_data_sets
    aging_issues = @issues.select { |issue| @cycletime.in_progress? issue }

    percentage = 85
    rules_to_issues = group_issues aging_issues
    data_sets = rules_to_issues.keys.collect do |rules|
      # aging_issues.collect(&:type).uniq.each do |type|
      {
        'type' => 'line',
        'label' => rules.label,
        'data' => rules_to_issues[rules].collect do |issue|
            age = @cycletime.age(issue)
            column = column_for issue: issue
            next if column.nil?

            { 'y' => age,
              'x' => column.name,
              'title' => ["#{issue.key} : #{issue.summary} (#{label_days age})"]
            }
          end.compact,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => rules.color
      }
    end
    data_sets << {
      'type' => 'bar',
      'label' => "#{percentage}%",
      'barPercentage' => 1.0,
      'categoryPercentage' => 1.0,
      'data' => days_at_percentage_threshold_for_all_columns(percentage: percentage, issues: @issues).drop(1)
    }
  end

  def days_at_percentage_threshold_for_all_columns percentage:, issues:
    accumulated_status_ids_per_column.collect do |_column, status_ids|
      ages = ages_of_issues_that_crossed_column_boundary issues: issues, status_ids: status_ids
      index = ages.size * percentage / 100
      ages.sort[index.to_i] || 0
    end
  end

  def accumulated_status_ids_per_column
    accumulated_status_ids = []
    board_columns.reverse.collect do |column|
      accumulated_status_ids += column.status_ids
      [column.name, accumulated_status_ids.dup]
    end.reverse
  end

  def ages_of_issues_that_crossed_column_boundary issues:, status_ids:
    issues.collect do |issue|
      stop = issue.first_time_in_status(*status_ids)
      start = @cycletime.started_time(issue)

      # Skip if either it hasn't crossed the boundary or we can't tell when it started.
      next if stop.nil? || start.nil?

      (stop.to_date - start.to_date).to_i + 1
    end.compact
  end

  def column_for issue:
    board_columns.find do |board_column|
      board_column.status_ids.include? issue.status.id
    end
  end
end
