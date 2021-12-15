# frozen_string_literal: true

class CycletimeScatterplot < ChartBase
  attr_accessor :issues, :cycletime

  def run
    completed_issues = @issues.select { |issue| @cycletime.done? issue }
    data_sets = []
    completed_issues.collect(&:type).uniq.each_with_index do |type|
      data_sets << {
        'label' => type,
        'data' => completed_issues
          .select { |issue| issue.type == type }
          .collect do |issue|
            cycle_time = @cycletime.cycletime(issue)
            { 'y' => cycle_time,
              'x' => @cycletime.stopped_time(issue),
              'title' => ["#{issue.key} : #{cycle_time} day#{'s' unless cycle_time == 1}",issue.summary]
            }
          end,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => color_for(type: type)
      }
    end

    render(binding, __FILE__)
  end
end
