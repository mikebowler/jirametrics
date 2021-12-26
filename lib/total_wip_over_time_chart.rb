# frozen_string_literal: true

require 'pathname'

class TotalWipOverTimeChart < ChartBase
  attr_accessor :issues, :cycletime, :date_range

  def run
    @daily_chart_items = DailyChartItemGenerator.new(
      issues: @issues, date_range: @date_range, cycletime: @cycletime
    ).run

    data_sets = []
    date_issues_list = @daily_chart_items.collect do |daily_chart_item|
      [daily_chart_item.date, daily_chart_item.completed_issues]
    end
    data_sets << daily_chart_dataset(
      date_issues_list: date_issues_list, color: '#009900', label: 'Completed', positive: false
    )

    [
      [29..nil, '#990000', 'More than four weeks'],
      [15..28, '#ce6300', 'Four weeks or less'],
      [8..14, '#ffd700', 'Two weeks or less'],
      [2..7, '#80bfff', 'A week or less'],
      [nil..1, '#aaaaaa', 'New today']
    ].each do |age_range, color, label|
      date_issues_list = @daily_chart_items.collect do |daily_chart_item|
        issues = daily_chart_item.active_issues.select do |issue|
          age = (daily_chart_item.date - @cycletime.started_time(issue).to_date).to_i + 1
          age_range.include? age
        end
        [daily_chart_item.date, issues]
      end

      data_sets << daily_chart_dataset(date_issues_list: date_issues_list, color: color, label: label) do |date, issue|
        "(age: #{label_days (date - @cycletime.started_time(issue)).to_i + 1})"
      end
    end

    render(binding, __FILE__)
  end
end
