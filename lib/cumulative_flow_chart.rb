# frozen_string_literal: true

require './lib/chart_base'

class CumulativeFlowChart < ChartBase
  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses, :date_range

  def run
    data_sets = @board_metadata.collect do |column|
      data_set_for_column column
    end
    render(binding, __FILE__)
  end

  def data_set_for_column column
    {
      type: 'line',
      label: column.name,
      data: data_for_column(column),
      fill: false,
      showLine: true,
      backgroundColor: 'red',
      pointBorderColor: 'black'
    }
  end

  def foo
    @issues.collect do |issue|
      @board_metadata.collect do |column|

      end
    end
  end

  def entered_column_at issue:, column:
    # puts "issue=#{issue.key} column=#{column.inspect}"
    issue.changes.each do |change|
      next unless change.status?

      # puts "#{column.status_ids.inspect} => #{change.value_id.inspect}"
      return change.time if column.status_ids.include? change.value_id
    end
    nil
  end

  def data_for_column column
    time_issue_pairs = @issues.collect do |issue|
      time = entered_column_at(issue: issue, column: column)
      [time, issue] if time
    end.compact.sort_by(&:first)

    count = 0
    time_issue_pairs.each do |time, issue|

      {
        y: closed_issues.size,
        x: "#{period.end}T23:59:59",
        title: ["#{closed_issues.size} items completed #{date_label}"] + closed_issues.collect { |_stop_date, issue| "#{issue.key} : #{issue.summary}" }
      }
    end
  end
end
