# frozen_string_literal: true

require 'pathname'

class TotalWipOverTimeChart < ChartBase
  attr_accessor :possible_statuses

  def initialize
    super()

    header_text 'Flow of Daily WIP'
    description_text <<-HTML
      <p>
        This chart shows the highest WIP on each given day. The WIP is color coded so you can see
        how old it is and hovering over the bar will show you exactly which work items it relates
        to. The green bar underneath, shows how many items completed on that day.
      </p>
      <p>
        "Completed without being started" reflects the fact that while we know that it completed
        that day, we were unable to determine when it had started. These items will not show up in
        the aging portion because we don't know when they started.
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
    @daily_chart_items = DailyChartItemGenerator.new(
      issues: @issues, date_range: @date_range, cycletime: @cycletime
    ).run

    data_sets = []
    data_sets << completed_dataset
    data_sets << completed_but_not_started_dataset

    [
      [29..nil, '#990000', 'More than four weeks'],
      [15..28, '#ce6300', 'Four weeks or less'],
      [8..14, '#ffd700', 'Two weeks or less'],
      [2..7, '#80bfff', 'A week or less'],
      [nil..1, '#aaaaaa', 'New today']
    ].each do |age_range, color, label|
      data_sets << age_range_dataset(age_range: age_range, color: color, label: label)
    end

    data_quality = scan_data_quality @issues

    wrap_and_render(binding, __FILE__)
  end

  def age_range_dataset age_range:, color:, label:
    date_issues_list = @daily_chart_items.collect do |daily_chart_item|
      issues = daily_chart_item.active_issues.select do |issue|
        age = (daily_chart_item.date - @cycletime.started_time(issue).to_date).to_i + 1
        age_range.include? age
      end
      [daily_chart_item.date, issues]
    end

    daily_chart_dataset(date_issues_list: date_issues_list, color: color, label: label) do |date, issue|
      "(age: #{label_days (date - @cycletime.started_time(issue).to_date).to_i + 1})"
    end
  end

  def completed_but_not_started_dataset
    hash = {}
    @issues.each do |issue|
      stopped = cycletime.stopped_time(issue)&.to_date
      next unless date_range.include? stopped

      (hash[stopped] ||= []) << issue if cycletime.started_time(issue).nil? && stopped
    end

    date_issues_list = hash.keys.sort.collect do |key|
      [key, hash[key]]
    end
    daily_chart_dataset(
      date_issues_list: date_issues_list,
      color: '#66FF66',
      label: 'Completed without having been started',
      positive: false
    )
  end

  def completed_dataset
    date_issues_list = @daily_chart_items.collect do |daily_chart_item|
      [daily_chart_item.date, daily_chart_item.completed_issues]
    end
    daily_chart_dataset(
      date_issues_list: date_issues_list, color: '#009900', label: 'Completed', positive: false
    )
  end
end
