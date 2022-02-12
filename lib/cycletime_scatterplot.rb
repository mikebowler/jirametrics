# frozen_string_literal: true

class CycletimeScatterplot < ChartBase
  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses, :date_range

  def initialize block = nil
    super()
    @group_by_block = block || ->(issue) { [issue.type, color_for(type: issue.type)] }
    @percentage_lines = []
  end

  def run
    completed_issues = @issues.select { |issue| @cycletime.stopped_time(issue) && @cycletime.started_time(issue) }

    data_sets = create_datasets completed_issues
    overall_percent_line = calculate_percent_line(completed_issues)
    @percentage_lines << [overall_percent_line, 'gray']

    data_quality = scan_data_quality completed_issues

    render(binding, __FILE__)
  end

  def create_datasets completed_issues
    data_sets = []

    groups = completed_issues.collect { |issue| @group_by_block.call(issue) }.uniq

    groups.each do |type|
      completed_issues_by_type = completed_issues.select { |issue| @group_by_block.call(issue) == type }
      label, color = *type
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
    {
      'y' => cycle_time,
      'x' => @cycletime.stopped_time(issue),
      'title' => ["#{issue.key} : #{issue.summary} (#{label_days(cycle_time)})"]
    }
  end

  def calculate_percent_line completed_issues
    times = completed_issues.collect { |issue| @cycletime.cycletime(issue) }
    index = times.size * 85 / 100
    times.sort[index]
  end
end
