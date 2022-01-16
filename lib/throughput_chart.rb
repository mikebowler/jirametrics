# frozen_string_literal: true

class ThroughputChart < ChartBase
  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses, :date_range

  def run
    completed_issues = @issues.select { |issue| @cycletime.stopped_time(issue) }

    data_sets = []
    data_sets << weekly_throughput_dataset(completed_issues: completed_issues)
    data_sets << daily_throughput_dataset(completed_issues: completed_issues)

    data_quality = scan_data_quality completed_issues

    render(binding, __FILE__)
  end

  def calculate_time_periods
    first_day = @date_range.begin
    first_day = case first_day.wday
      when 0 then first_day + 1
      when 1 then first_day
      else first_day + (8 - first_day.wday)
    end

    periods = []

    loop do
      last_day = first_day + 6
      return periods unless @date_range.include? last_day

      periods << (first_day..last_day)
      first_day = last_day + 1
    end
  end

  def daily_throughput_dataset completed_issues:
    {
      label: 'Daily throughput',
      data: throughput_dataset(periods: date_range.collect { |date| date..date }, completed_issues: completed_issues),
      fill: false,
      showLine: true,
      lineTension: 0.4,
      backgroundColor: 'gray'
    }
  end

  def weekly_throughput_dataset completed_issues:
    {
      label: 'Weekly throughput',
      data: throughput_dataset(periods: calculate_time_periods, completed_issues: completed_issues),
      fill: false,
      showLine: true,
      borderColor: 'blue',
      lineTension: 0.4,
      backgroundColor: 'blue'
    }
  end

  def throughput_dataset periods:, completed_issues:
    periods.collect do |period|
      closed_issues = completed_issues.collect do |issue|
        stop_date = cycletime.stopped_time(issue)&.to_date
        [stop_date, issue] if stop_date && period.include?(stop_date)
      end.compact

      { y: closed_issues.size,
        x: period.end,
        title: ["#{closed_issues.size} items completed"] + closed_issues.collect { |_stop_date, issue| "#{issue.key} : #{issue.summary}" }
      }
    end
  end
end
