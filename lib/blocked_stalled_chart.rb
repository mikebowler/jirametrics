# frozen_string_literal: true

require './lib/chart_base'
require './lib/daily_chart_item_generator'

class BlockedStalledChart < ChartBase
  attr_accessor :possible_statuses

  def initialize
    super()

    header_text 'Blocked or stalled work'
    description_text <<-HTML
      <p>
        This chart shows all active (started but not completed) work, ordered from oldest at the top to
        newest at the bottom.
      </p>
      <p>
        The colours indicate different statuses, grouped by status category. Any
        statuses in the status category of "To Do" will be in a shade of blue. Any in the category of
        "In Progress" will be in a shade of yellow and any in "Done" will be in a shade of green.
        Depending on how you calculate cycletime, you may end up with only yellows or you may have a mix
        of all three.
      </p>
      <p>
        The gray backgrounds indicate weekends and the red vertical line indicates the 85% point for all
        items in this time period. Anything that started to the left of that is now an outlier.
      </p>
    HTML
    check_data_quality_for(
      :completed_but_not_started,
      :status_changes_after_done,
      :backwords_through_statuses,
      :backwards_through_status_categories,
      :created_in_wrong_status,
      :status_not_on_board
    )
  end

  def run
    stalled_threshold = 5
    daily_chart_items = DailyChartItemGenerator.new(
      issues: @issues, date_range: @date_range, cycletime: @cycletime
    ).run

    data_sets = make_data_sets daily_chart_items: daily_chart_items, stalled_threshold: stalled_threshold
    data_quality = scan_data_quality @issues

    wrap_and_render(binding, __FILE__)
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
