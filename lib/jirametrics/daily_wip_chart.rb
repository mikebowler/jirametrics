# frozen_string_literal: true

require 'jirametrics/chart_base'

class DailyGroupingRules < GroupingRules
  attr_accessor :current_date, :group_priority, :issue_hint

  def initialize
    super()
    @group_priority = 0
  end
end

class DailyWipChart < ChartBase
  attr_accessor :possible_statuses

  def initialize block = nil
    super()

    header_text default_header_text
    description_text default_description_text

    if block
      instance_eval(&block)
    else
      grouping_rules do |issue, rules|
        default_grouping_rules issue: issue, rules: rules
      end
    end
  end

  def run
    issue_rules_by_active_date = group_issues_by_active_dates
    possible_rules = select_possible_rules issue_rules_by_active_date

    data_sets = possible_rules.collect do |grouping_rule|
      make_data_set grouping_rule: grouping_rule, issue_rules_by_active_date: issue_rules_by_active_date
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
      cycletime = issue.board.cycletime
      start = cycletime.started_time(issue)&.to_date
      stop = cycletime.stopped_time(issue)&.to_date
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
      borderColor: 'gray',
      borderWidth: grouping_rule.color.to_s == 'var(--body-background)' ? 1 : 0,
      borderRadius: positive ? 0 : 5
    }
  end

  def configure_rule issue:, date:
    raise 'grouping_rules must be set' if @group_by_block.nil?

    rules = DailyGroupingRules.new
    rules.current_date = date
    @group_by_block.call issue, rules
    rules
  end

  def grouping_rules &block
    @group_by_block = block
  end
end
