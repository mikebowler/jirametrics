# frozen_string_literal: true

require './lib/chart_base'
require './lib/daily_chart_item_generator'

class BlockedStalledChart < ChartBase
  attr_accessor :issues, :cycletime, :date_range

  def run
    stalled_threshold = 5
    daily_chart_items = DailyChartItemGenerator.new(
      issues: @issues, date_range: @date_range, cycletime: @cycletime
    ).run

    data_sets = make_data_sets daily_chart_items: daily_chart_items, stalled_threshold: stalled_threshold
    render(binding, __FILE__)
  end

  def make_data_sets daily_chart_items:, stalled_threshold:
    blocked_data = []
    stalled_data = []
    active_data = []
    completed_data = []

    daily_chart_items.each do |item|
      blocked, stalled = blocked_stalled(
        date: item.date, issues: item.active_issues, stalled_threshold: stalled_threshold
      )

      blocked_data << [item.date, blocked]
      stalled_data << [item.date, stalled]
      completed_data << [item.date, item.completed_issues]
      active_data << [item.date, item.active_issues - blocked - stalled]
    end

    data_sets = []
    data_sets << daily_chart_dataset(date_issues_list: blocked_data, color: 'red', label: 'blocked')
    data_sets << daily_chart_dataset(date_issues_list: stalled_data, color: 'orange', label: 'stalled')
    data_sets << daily_chart_dataset(date_issues_list: active_data, color: 'lightgray', label: 'active')

    data_sets
  end

  def blocked_stalled date:, issues:, stalled_threshold:
    # If an item is both blocked and stalled, it should show up only in the blocked list.
    blocked = issues.select { |issue| issue.blocked_on_date? date }
    stalled = issues.select { |issue| issue.stalled_on_date? date, stalled_threshold } - blocked
    [blocked, stalled]
  end
end
