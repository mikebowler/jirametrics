# frozen_string_literal: true

class ThroughputChart < ChartBase
  attr_accessor :issues, :cycletime, :board_columns, :possible_statuses, :date_range

  def initialize block = nil
    super()
    @group_by_block = block || ->(_issue) { %w[Throughput blue] }
  end

  def run
    completed_issues = @issues.select { |issue| @cycletime.stopped_time(issue) }

    data_sets = []
    groups = completed_issues.collect { |issue| @group_by_block.call(issue) }.uniq
    groups.each do |type|
      completed_issues_by_type = completed_issues.select { |issue| @group_by_block.call(issue) == type }
      label, color = *type
      data_sets << weekly_throughput_dataset(completed_issues: completed_issues_by_type, label: label, color: color)
    end

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

  def weekly_throughput_dataset completed_issues:, label:, color:
    {
      label: label,
      data: throughput_dataset(periods: calculate_time_periods, completed_issues: completed_issues),
      fill: false,
      showLine: true,
      borderColor: color,
      lineTension: 0.4,
      backgroundColor: color
    }
  end

  def throughput_dataset periods:, completed_issues:
    periods.collect do |period|
      closed_issues = completed_issues.collect do |issue|
        stop_date = cycletime.stopped_time(issue)&.to_date
        [stop_date, issue] if stop_date && period.include?(stop_date)
      end.compact

      date_label = "on #{period.end}"
      date_label = "between #{period.begin} and #{period.end}" unless period.begin == period.end

      { y: closed_issues.size,
        x: "#{period.end}T23:59:59",
        title: ["#{closed_issues.size} items completed #{date_label}"] + closed_issues.collect { |_stop_date, issue| "#{issue.key} : #{issue.summary}" }
      }
    end
  end
end
