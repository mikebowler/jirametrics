# frozen_string_literal: true

class CycletimeScatterplot < ChartBase
  attr_accessor :issues, :cycletime

  def run
    completed_issues = @issues.select { |issue| @cycletime.stopped_time(issue) && @cycletime.started_time(issue) }

    data_sets = create_datasets completed_issues
    percent_line = calculate_percent_line completed_issues
    stopped_but_not_started_count = @issues.count do |issue|
      @cycletime.stopped_time(issue) && @cycletime.started_time(issue).nil?
    end

    render(binding, __FILE__)
  end

  def create_datasets completed_issues
    data_sets = []

    completed_issues.collect(&:type).uniq.sort.each do |type|
      completed_issues_by_type = completed_issues.select { |issue| issue.type == type }
      data_sets << {
        'label' => type,
        'data' => completed_issues_by_type.collect { |issue| data_for_issue(issue) }.compact,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => color_for(type: type)
      }
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
