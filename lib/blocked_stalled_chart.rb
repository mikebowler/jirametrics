# frozen_string_literal: true

require './lib/chart_base'
require './lib/daily_chart_item_generator'

class BlockedStalledChart < ChartBase
  attr_accessor :issues, :cycletime, :date_range

  def run
    stalled_threshold = 5
    @daily_chart_items = DailyChartItemGenerator.new(
      issues: @issues, date_range: @date_range, cycletime: @cycletime
    ).run

    data_sets = make_data_sets stalled_threshold: stalled_threshold
    render(binding, __FILE__)
  end

  def make_data_sets stalled_threshold:
    data_sets = []

    blocked_data = []
    stalled_data = []
    active_data = []
    completed_data = []

    @daily_chart_items.each do |daily_chart_item|
      blocked = daily_chart_item.active_issues.select { |issue| issue.blocked_on_date? daily_chart_item.date }
      stalled = daily_chart_item.active_issues.select { |issue| daily_chart_item.date - issue.updated >= stalled_threshold }

      blocked_data << [daily_chart_item.date, blocked]
      stalled_data << [daily_chart_item.date, stalled]
      completed_data << [daily_chart_item.date, daily_chart_item.completed_issues]
      active_data << [daily_chart_item.date, daily_chart_item.active_issues - blocked - stalled]
    end

    data_sets << active_dataset(date_issues_list: blocked_data, color: 'red', label: 'blocked')
    data_sets << active_dataset(date_issues_list: stalled_data, color: 'orange', label: 'stalled')
    data_sets << active_dataset(date_issues_list: active_data, color: 'lightgray', label: 'active')
    data_sets << completed_dataset(date_issues_list: completed_data, color: '#009900', label: 'completed')

    data_sets
  end

  def active_dataset date_issues_list:, color:, label:
    {
      type: 'bar',
      label: label,
      data: date_issues_list.collect do |date, issues|
        {
          x: date,
          y: issues.size,
          title: [label] + issues.collect { |i| "#{i.key} : #{i.summary}" }.sort
        }
      end,
      backgroundColor: color
    }
  end

  def completed_dataset date_issues_list:, color:, label:
    {
      type: 'bar',
      label: label,
      data: date_issues_list.collect do |date, issues|
        {
          x: date,
          y: -issues.size,
          title: [label] + issues.collect { |i| "#{i.key} : #{i.summary}" }.sort
        }
      end,
      backgroundColor: color,
      borderRadius: 5
    }
  end
end
