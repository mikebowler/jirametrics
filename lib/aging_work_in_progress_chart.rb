# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkInProgressChart < ChartBase
  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses

  def run
    data_sets = make_data_sets
    column_headings = board_metadata.collect(&:name)

    data_quality = scan_data_quality @issues

    render(binding, __FILE__)
  end

  def make_data_sets
    aging_issues = @issues.select { |issue| @cycletime.in_progress? issue }

    percentage = 85
    data_sets = []
    aging_issues.collect(&:type).uniq.each do |type|
      data_sets << {
        'type' => 'line',
        'label' => type,
        'data' => aging_issues.select { |issue| issue.type == type }.collect do |issue|
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
        'backgroundColor' => color_for(type: type)
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
    @board_metadata.reverse.collect do |column|
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

      (stop - start).to_i + 1
    end.compact
  end

  def column_for issue:
    @board_metadata.find do |board_column|
      board_column.status_ids.include? issue.status_id
    end
  end
end
