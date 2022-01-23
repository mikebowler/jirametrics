# frozen_string_literal: true

class DailyChartItemGenerator
  class DailyChartItem
    attr_reader :date
    attr_accessor :active_issues, :completed_issues, :cycletime

    def initialize date:, active_issues: nil, completed_issues: nil
      @date = date
      @active_issues = active_issues
      @completed_issues = completed_issues
    end
  end

  attr_reader :daily_chart_items

  def initialize issues:, date_range:, cycletime:
    @issues = issues
    @date_range = date_range
    @cycletime = cycletime

    @daily_chart_items = @date_range.collect do |date|
      DailyChartItem.new(date: date)
    end
  end

  def daily_chart_item date:
    @daily_chart_items.bsearch { |item| date <=> item.date }
  end

  def close_off_previous_date previous_date:, active_issues:, completed_issues:
    return unless @date_range.include? previous_date

    item = daily_chart_item date: previous_date
    item.completed_issues = completed_issues
    item.active_issues = active_issues.dup + completed_issues
  end

  def run
    populate_days start_stop_sequence: make_start_stop_sequence_for_issues
    fill_in_gaps
  end

  def populate_days start_stop_sequence:
    active = []
    completed = []
    previous_date = nil

    start_stop_sequence.each do |time, action, issue|
      date = time.to_date
      if @date_range.include?(date) && date != previous_date
        close_off_previous_date previous_date: previous_date, active_issues: active, completed_issues: completed
        completed = []
      end

      case action
      when 'start'
        active << issue
      when 'stop'
        active.delete issue
        completed << issue
      else
        raise "Unexpected action: #{action}"
      end

      previous_date = date
    end
    close_off_previous_date previous_date: previous_date, active_issues: active, completed_issues: completed
  end

  def fill_in_gaps
    if @daily_chart_items.first.active_issues.nil?
      # This is an odd case where we couldn't find any earlier data at all so we have to assume that
      # nothing is in progress.
      @daily_chart_items.first.active_issues = []
      @daily_chart_items.first.completed_issues = []
    end

    @daily_chart_items.each_with_index do |item, index|
      next if item.active_issues

      previous_item = @daily_chart_items[index - 1]
      item.active_issues = previous_item.active_issues - previous_item.completed_issues
      item.completed_issues = []
    end
  end

  # Returns a list of tuples [time, action(start or stop), issue] in sorted order
  def make_start_stop_sequence_for_issues
    list = []
    @issues.each do |issue|
      started = @cycletime.started_time(issue)
      stopped = @cycletime.stopped_time(issue)
      next unless started

      list << [started, 'start', issue]
      list << [@cycletime.stopped_time(issue), 'stop', issue] unless stopped.nil?
    end
    list.sort { |a, b| a.first <=> b.first }
  end

  # Returns a flattened list that's easier to assert against.
  def to_test
    @daily_chart_items.collect do |item|
      [item.date.to_s, item.active_issues, item.completed_issues]
    end
  end
end
