# frozen_string_literal: true

class CycletimeScatterplot < ChartBase
  attr_accessor :issues, :cycletime

  def run
    data_sets = create_datasets
    render(binding, __FILE__)
  end

  def create_datasets
    data_sets = []
    completed_issues = @issues.select { |issue| @cycletime.done? issue }
    completed_issues.collect(&:type).uniq.sort.each do |type|
      completed_issues_by_type = completed_issues.select { |issue| issue.type == type }
      data_sets << {
        'label' => type,
        'data' => completed_issues_by_type.collect { |issue| data_for_issue(issue) },
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
end
