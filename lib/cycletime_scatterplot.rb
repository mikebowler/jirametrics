# frozen_string_literal: true

require './lib/groupable_issue_chart'

class CycletimeScatterplot < ChartBase
  include GroupableIssueChart

  attr_accessor :possible_statuses

  def initialize block = nil
    super()

    init_configuration_block block do
      grouping_rules do |issue, rule|
        rule.label = issue.type
        rule.color = color_for type: issue.type
      end
    end

    @percentage_lines = []
    @highest_cycletime = 0
  end

  def run
    completed_issues = completed_issues_in_range include_unstarted: false

    data_sets = create_datasets completed_issues
    overall_percent_line = calculate_percent_line(completed_issues)
    @percentage_lines << [overall_percent_line, 'gray']

    data_quality = scan_data_quality(@issues.select { |issue| @cycletime.stopped_time(issue) })

    render(binding, __FILE__)
  end

  def create_datasets completed_issues
    data_sets = []

    groups = group_issues completed_issues
    # groups = completed_issues.collect { |issue| @group_by_block.call(issue) }.uniq

    groups.each_key do |rules|
      # completed_issues_by_type = completed_issues.select { |issue| @group_by_block.call(issue) == type }
      completed_issues_by_type = groups[rules]
      label = rules.label
      color = rules.color
      # label, color = *type
      percent_line = calculate_percent_line completed_issues_by_type
      data_sets << {
        'label' => "#{label} (85% at #{label_days(percent_line)})",
        'data' => completed_issues_by_type.collect { |issue| data_for_issue(issue) }.compact,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => color
      }
      @percentage_lines << [percent_line, color]
    end
    data_sets
  end

  def data_for_issue issue
    cycle_time = @cycletime.cycletime(issue)
    @highest_cycletime = cycle_time if @highest_cycletime < cycle_time

    {
      'y' => cycle_time,
      'x' => chart_format(@cycletime.stopped_time(issue)),
      'title' => ["#{issue.key} : #{issue.summary} (#{label_days(cycle_time)})"]
    }
  end

  def calculate_percent_line completed_issues
    times = completed_issues.collect { |issue| @cycletime.cycletime(issue) }
    index = times.size * 85 / 100
    times.sort[index]
  end
end
