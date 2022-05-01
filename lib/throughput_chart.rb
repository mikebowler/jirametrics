# frozen_string_literal: true

class ThroughputChart < ChartBase
  include GroupableIssueChart

  attr_accessor :possible_statuses


  def initialize block = nil
    super()

    init_configuration_block(block) do
      grouping_rules do |issue, rule|
        rule.label = issue.type
        rule.color = color_for type: issue.type
      end
    end
  end

  def run
    completed_issues = completed_issues_in_range include_unstarted: true
    rules_to_issues = group_issues completed_issues

    data_sets = []
    if rules_to_issues.size > 1
      data_sets << weekly_throughput_dataset(
        completed_issues: completed_issues, label: 'Totals', color: 'gray', dashed: true
      )
    end

    rules_to_issues.each_key do |rules|
      data_sets << weekly_throughput_dataset(
        completed_issues: rules_to_issues[rules], label: rules.label, color: rules.color
      )
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

  def weekly_throughput_dataset completed_issues:, label:, color:, dashed: false
    result = {
      label: label,
      data: throughput_dataset(periods: calculate_time_periods, completed_issues: completed_issues),
      fill: false,
      showLine: true,
      borderColor: color,
      lineTension: 0.4,
      backgroundColor: color
    }
    result['borderDash'] = [10, 5] if dashed
    result
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
