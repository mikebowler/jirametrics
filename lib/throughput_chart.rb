# frozen_string_literal: true

class ThroughputChart < ChartBase
  attr_accessor :possible_statuses

  class GroupingRules < Rules
    attr_accessor :label, :color
  end

  def initialize block = nil
    super()
    @rules_block = block

    if block && block.arity == 1
      puts 'DEPRECATED: ThroughputChart: Use the new grouping_rules syntax'
      grouping_rules do |issue, rules|
        rules.label, rules.color = block.call(issue)
      end
      @rules_block = nil
    end
  end

  def run
    instance_eval(&@rules_block) if @rules_block

    completed_issues = completed_issues_in_range include_unstarted: true
    rules_to_issues = group_issues completed_issues

    data_sets = []
    rules_to_issues.each_key do |rules|
      data_sets << weekly_throughput_dataset(
        completed_issues: rules_to_issues[rules], label: rules.label, color: rules.color
      )
    end

    data_quality = scan_data_quality completed_issues

    render(binding, __FILE__)
  end

  def grouping_rules &block
    @group_by_block = block
  end

  def group_issues completed_issues
    if @group_by_block.nil?
      grouping_rules do |_issue, rules|
        rules.label = 'Throughput'
        rules.color = 'blue'
      end
    end

    result = {}
    completed_issues.each do |issue|
      rules = GroupingRules.new
      @group_by_block.call(issue, rules)
      next if rules.ignored?

      (result[rules] ||= []) << issue
    end
    result
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
