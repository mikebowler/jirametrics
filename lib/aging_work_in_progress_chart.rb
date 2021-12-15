# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkInProgressChart < ChartBase
  attr_accessor :issues, :board_metadata, :cycletime

  def run
    aging_issues = @issues.select { |issue| @cycletime.in_progress? issue }

    data_sets = []
    aging_issues.collect(&:type).uniq.each_with_index do |type|
      data_sets << {
        'type' => 'line',
        'label' => type,
        'data' => aging_issues
          .select { |issue| issue.type == type }
          .collect do |issue|
            age = @cycletime.age(issue)
            { 'y' => @cycletime.age(issue),
              'x' => (column_for issue: issue, board_metadata: @board_metadata).name,
              'title' => ["#{issue.key} : #{age} day#{'s' unless age == 1}", issue.summary]
            }
          end,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => color_for(type: type)
      }
    end
    data_sets << {
      type: 'bar',
      label: '85%',
      barPercentage: 1.0,
      categoryPercentage: 1.0,
      data: days_at_percentage_threshold_for_all_columns(
        percentage: 85, issues: @issues, columns: board_metadata
      ).drop(1)
    }

    column_headings = board_metadata.collect(&:name)
    render(binding, __FILE__)
  end

  def days_at_percentage_threshold_for_all_columns percentage:, issues:, columns:
    accumulated_status_ids = []
    columns.reverse.collect do |column|
      accumulated_status_ids += column.status_ids
      date_that_percentage_of_issues_leave_statuses(
        percentage: percentage, issues: issues, status_ids: accumulated_status_ids
      )
    end.reverse
  end

  def date_that_percentage_of_issues_leave_statuses percentage:, issues:, status_ids:
    days_to_transition = issues.collect do |issue|
      transition_time = issue.first_time_in_status(*status_ids)
      if transition_time.nil?
        # This item has never left this particular column. Exclude it from the
        # calculation
        nil
      else
        start_time = @cycletime.started_time(issue)
        if start_time.nil?
          # This item went straight from created to done so we can't determine the
          # start time. Exclude this record from the calculation
          nil
        else
          (transition_time - start_time).to_i + 1
        end
      end
    end.compact
    index = days_to_transition.size * percentage / 100
    days_to_transition.sort[index.to_i]
  end

  def column_for issue:, board_metadata:
    board_metadata.find do |board_column|
      board_column.status_ids.include? issue.status_id
    end
  end
end