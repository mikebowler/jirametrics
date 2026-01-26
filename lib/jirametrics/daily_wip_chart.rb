# frozen_string_literal: true

require 'jirametrics/chart_base'

class DailyGroupingRules < GroupingRules
  attr_accessor :current_date, :group_priority, :issue_hint

  def initialize
    super
    @group_priority = 0
  end
end

class DailyWipChart < ChartBase
  attr_accessor :possible_statuses

  def initialize block
    super()

    header_text default_header_text
    description_text default_description_text

    instance_eval(&block) if block

    return if @group_by_block

    grouping_rules do |issue, rules|
      default_grouping_rules issue: issue, rules: rules
    end
  end

  def run
    issue_rules_by_active_date = group_issues_by_active_dates
    possible_rules = select_possible_rules issue_rules_by_active_date

    data_sets = possible_rules.collect do |grouping_rule|
      make_data_set grouping_rule: grouping_rule, issue_rules_by_active_date: issue_rules_by_active_date
    end
    if @trend_lines
      data_sets = @trend_lines.filter_map do |group_labels, line_color|
        trend_line_data_set(data: data_sets, group_labels: group_labels, color: line_color)
      end + data_sets
    end

    wrap_and_render(binding, __FILE__)
  end

  def default_header_text = 'Daily WIP'
  def default_description_text = ''

  def default_grouping_rules issue:, rules: # rubocop:disable Lint/UnusedMethodArgument
    raise 'If you use this class directly then you must provide grouping_rules'
  end

  def select_possible_rules issue_rules_by_active_date
    possible_rules = []
    issue_rules_by_active_date.each_pair do |_date, issues_rules_list|
      issues_rules_list.each do |_issue, rules| # rubocop:disable Style/HashEachMethods
        possible_rules << rules unless possible_rules.any? { |r| r.group == rules.group }
      end
    end
    possible_rules.sort_by!(&:group_priority)
  end

  def group_issues_by_active_dates
    hash = {}

    @issues.each do |issue|
      start, stop = cycletime_for_issue(issue).started_stopped_dates(issue)
      next if start.nil? && stop.nil?

      # If it stopped but never started then assume it started at creation so the data points
      # will be available for the config.
      start = issue.created.to_date if stop && start.nil?
      start = @date_range.begin if start < @date_range.begin

      start.upto(stop || @date_range.end) do |date|
        rule = configure_rule issue: issue, date: date
        (hash[date] ||= []) << [issue, rule] unless rule.ignored?
      end
    end
    hash
  end

  def make_data_set grouping_rule:, issue_rules_by_active_date:
    positive = grouping_rule.group_priority >= 0

    data = issue_rules_by_active_date.collect do |date, issue_rules|
      # issues = []
      issue_strings = issue_rules
        .select { |_issue, rules| rules.group == grouping_rule.group }
        .sort_by { |issue, _rules| issue.key_as_i }
        .collect { |issue, rules| "#{issue.key} : #{issue.summary.strip} #{rules.issue_hint}" }
      title = ["#{grouping_rule.label} (#{label_issues issue_strings.size})"] + issue_strings

      {
        x: date,
        y: positive ? issue_strings.size : -issue_strings.size,
        title: title
      }
    end

    {
      type: 'bar',
      label: grouping_rule.label,
      data: data,
      backgroundColor: grouping_rule.color || random_color,
      borderColor: CssVariable['--wip-chart-border-color'],
      borderWidth: grouping_rule.color.to_s == 'var(--body-background)' ? 1 : 0,
      borderRadius: positive ? 0 : 5
    }
  end

  def configure_rule issue:, date:
    raise "#{self.class}: grouping_rules must be set" if @group_by_block.nil?

    rules = DailyGroupingRules.new
    rules.current_date = date
    @group_by_block.call issue, rules
    rules
  end

  def grouping_rules &block
    @group_by_block = block
  end

  def add_trend_line group_labels:, line_color:
    (@trend_lines ||= []) << [group_labels, line_color]
  end

  def trend_line_data_set data:, group_labels:, color:
    day_wip_hash = {}
    data.each do |top_level|
      next unless group_labels.include? top_level[:label]

      top_level[:data].each do |datapoint|
        date = datapoint[:x]
        day_wip_hash[date] = (day_wip_hash[date] || 0) + datapoint[:y]
      end
    end

    points = day_wip_hash
      .collect { |date, wip| [date.jd, wip] }
      .sort_by(&:first)

    calculator = TrendLineCalculator.new(points)
    return nil unless calculator.valid?

    data_points = calculator.chart_datapoints(
      range: date_range.begin.jd..date_range.end.jd,
      max_y: points.collect { |_date, wip| wip }.max
    )
    data_points.each do |point_hash|
      point_hash[:x] = chart_format Date.jd(point_hash[:x])
    end

    {
      type: 'line',
      label: 'Trendline',
      data: data_points,
      fill: false,
      borderWidth: 1,
      markerType: 'none',
      borderColor: CssVariable[color],
      borderDash: [6, 3],
      pointStyle: 'dash',
      hidden: false
    }
  end
end
