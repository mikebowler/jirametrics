# frozen_string_literal: true

require './lib/groupable_issue_chart'

class CycletimeScatterplot < ChartBase
  include GroupableIssueChart

  attr_accessor :possible_statuses

  def initialize block = nil
    super()

    header_text 'Cycletime Scatterplot'
    description_text <<-HTML
      <p>
        This chart shows only completed work and indicates both what day it completed as well as
        how many days it took to get done. Hovering over a dot will show you the ID of the work item.
      </p>
      <p>
        The gray line indicates the 85th percentile (<%= overall_percent_line %> days). 85% of all
        items on this chart fall on or below the line and the remaining 15% are above the line. 85%
        is a reasonable proxy for "most" so that we can say that based on this data set, we can
        predict that most work of this type will complete in <%= overall_percent_line %> days or
        less. The other lines reflect the 85% line for that respective type of work.
      </p>
      <p>
        The gray vertical bars indicate weekends, when theoretically we aren't working.
      </p>
    HTML
    check_data_quality_for(
      :status_changes_after_done,
      :completed_but_not_started,
      :backwords_through_statuses,
      :backwards_through_status_categories,
      :created_in_wrong_status,
      :status_not_on_board
    )

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

    wrap_and_render(binding, __FILE__)
  end

  def create_datasets completed_issues
    data_sets = []

    groups = group_issues completed_issues

    groups.each_key do |rules|
      completed_issues_by_type = groups[rules]
      label = rules.label
      color = rules.color
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
