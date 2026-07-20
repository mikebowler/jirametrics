# frozen_string_literal: true

require 'jirametrics/chart_base'

class DailyGroupingRules < GroupingRules
  attr_accessor :current_date, :group_priority, :issue_hint, :highlight

  def initialize
    super
    @group_priority = 0
  end

  def group
    [@label, @color, @highlight ? true : false]
  end
end

class DailyWipChart < ChartBase
  attr_accessor :possible_statuses

  def initialize block
    super()

    header_text default_header_text
    description_text default_description_text
    @x_axis_title = nil
    @y_axis_title = 'Count of items'

    instance_eval(&block) if block

    return if @group_by_block

    grouping_rules do |issue, rules|
      default_grouping_rules issue: issue, rules: rules
    end
  end

  def run
    issue_rules_by_active_date = group_issues_by_active_dates
    possible_rules = select_possible_rules issue_rules_by_active_date

    data_sets = build_data_sets(possible_rules, issue_rules_by_active_date)
    data_sets = prepend_trend_lines(data_sets) if @trend_lines

    wrap_and_render(binding, __FILE__)
  end

  def build_data_sets possible_rules, issue_rules_by_active_date
    labels = conflicting_labels(possible_rules)
    possible_rules.collect do |grouping_rule|
      suffix = labels.include?(grouping_rule.label) && grouping_rule.highlight ? '*' : ''
      make_data_set grouping_rule: grouping_rule, issue_rules_by_active_date: issue_rules_by_active_date,
                    label_suffix: suffix
    end
  end

  # Labels that appear both highlighted and un-highlighted; the highlighted variant gets a '*' suffix so
  # the two are distinguishable in the legend.
  def conflicting_labels possible_rules
    possible_rules
      .group_by(&:label)
      .select { |_label, rules| rules.any?(&:highlight) && rules.any? { |rule| !rule.highlight } }
      .keys
  end

  def prepend_trend_lines data_sets
    @trend_lines.filter_map do |group_labels, line_color|
      trend_line_data_set(data: data_sets, group_labels: group_labels, color: line_color)
    end + data_sets
  end

  def default_header_text = 'Daily WIP'
  def default_description_text = ''

  def default_grouping_rules issue:, rules:
    raise 'If you use this class directly then you must provide grouping_rules'
  end

  def select_possible_rules issue_rules_by_active_date
    possible_rules = []
    issue_rules_by_active_date.each_pair do |_date, issues_rules_list|
      # issues_rules_list is an array of [issue, rule] pairs, not a hash, so this isn't each_value.
      issues_rules_list.each do |_issue, rules| # rubocop:disable Style/HashEachMethods
        possible_rules << rules unless possible_rules.any? { |r| r.group == rules.group }
      end
    end
    possible_rules.sort_by!(&:group_priority)
  end

  def group_issues_by_active_dates
    hash = {}
    @issues.each do |issue|
      active_dates_for(issue)&.each do |date|
        rule = configure_rule issue: issue, date: date
        (hash[date] ||= []) << [issue, rule] unless rule.ignored?
      end
    end
    hash
  end

  # The range of dates an issue is "active" on the chart: from when it started - or its creation, if it
  # stopped without a recorded start - through when it stopped, or the end of the range if still open.
  # Returns nil when the issue neither started nor stopped.
  def active_dates_for issue
    start, stop = cycletime_for_issue(issue).started_stopped_dates(issue)
    return nil if start.nil? && stop.nil?

    # Past the guard, a nil start means it only stopped, so treat creation as the start.
    start = issue.created.to_date if start.nil?
    start = @date_range.begin if start < @date_range.begin
    start..(stop || @date_range.end)
  end

  def make_data_set grouping_rule:, issue_rules_by_active_date:, label_suffix: ''
    positive = grouping_rule.group_priority >= 0
    display_label = "#{grouping_rule.label}#{label_suffix}"

    data = issue_rules_by_active_date.collect do |date, issue_rules|
      datapoint_for date: date, issue_rules: issue_rules, grouping_rule: grouping_rule,
                    display_label: display_label, positive: positive
    end

    {
      type: 'bar',
      label: display_label,
      label_hint: grouping_rule.label_hint,
      data: data,
      backgroundColor: background_color_for(grouping_rule),
      borderColor: CssVariable['--wip-chart-border-color'],
      borderWidth: grouping_rule.color.to_s == 'var(--body-background)' ? 1 : 0,
      borderRadius: positive ? 0 : 5
    }
  end

  # One {x, y, title} point: the issues active on this date that belong to this rule's group, with a
  # title listing them. y is negated for negative-priority groups so they render below the axis.
  def datapoint_for date:, issue_rules:, grouping_rule:, display_label:, positive:
    issue_strings = issue_strings_for issue_rules, grouping_rule
    title_label = grouping_rule.label_hint || display_label
    title = ["#{title_label} (#{label_issues issue_strings.size})"] + issue_strings

    { x: date, y: positive ? issue_strings.size : -issue_strings.size, title: title }
  end

  def issue_strings_for issue_rules, grouping_rule
    issue_rules
      .select { |_issue, rules| rules.group == grouping_rule.group }
      .sort_by { |issue, _rules| issue.key_as_i }
      .collect { |issue, rules| "#{issue.key} : #{issue.summary.strip} #{rules.issue_hint}" }
  end

  def background_color_for grouping_rule
    color = grouping_rule.color || random_color
    return color unless grouping_rule.highlight

    RawJavascript.new("createDiagonalPattern(#{color.to_json})")
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

  # Sums the daily WIP across every dataset whose label is in group_labels, giving { date => total_wip }.
  def daily_wip_totals data, group_labels
    day_wip_hash = {}
    data.each do |top_level|
      next unless group_labels.include? top_level[:label]

      top_level[:data].each do |datapoint|
        date = datapoint[:x]
        day_wip_hash[date] = (day_wip_hash[date] || 0) + datapoint[:y]
      end
    end
    day_wip_hash
  end

  def trend_line_data_set data:, group_labels:, color:
    points = daily_wip_totals(data, group_labels)
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
