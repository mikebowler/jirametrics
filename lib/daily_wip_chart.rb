# frozen_string_literal: true

require './lib/chart_base'
require './lib/daily_chart_item_generator'

class DailyGroupingRules < GroupingRules
  attr_accessor :current_date, :group_priority, :issue_hint

  def initialize
    super()
    @group_priority = 0
  end

end

class DailyWipChart < ChartBase
  attr_accessor :possible_statuses

  def initialize block
    super()

    if block
      instance_eval(&block)
    else
      run_default_config
    end

    check_data_quality_for(
      :completed_but_not_started,
      :status_changes_after_done,
      :backwords_through_statuses,
      :backwards_through_status_categories,
      :created_in_wrong_status,
      :status_not_on_board,
      :stopped_before_started
    )
  end

  def run_default_config
    header_text 'Daily WIP Chart - base'
    description_text <<-HTML
      <p>
        This chart highlights aging work, grouped by type
      </p>
    HTML

    grouping_rules do |issue, rules|
      started = cycletime.started_time(issue)&.to_date
      stopped = cycletime.stopped_time(issue)&.to_date

      rules.issue_hint = "(age: #{label_days (rules.current_date - started + 1).to_i})" if started

      if stopped && started.nil? # We can't tell when it started
        if stopped == rules.current_date
          rules.label = 'Completed but not started'
          rules.color = '#66FF66'
          rules.group_priority = -1
        elsif rules.current_date >= issue.created.to_date && rules.current_date < stopped
          # We're past the creation date but it isn't done yet
          rules.label = 'Cannot tell when it started'
          rules.color = 'white'
          rules.group_priority = 11
          created_days = rules.current_date - issue.created.to_date + 1
          rules.issue_hint = "(created: #{label_days created_days.to_i} earlier, stopped on #{stopped})"
        end
      elsif stopped == rules.current_date
        rules.label = 'Completed'
        rules.color = '#009900'
        rules.group_priority = -2
      else
        age = rules.current_date - started + 1

        case age
        when ..0
          puts 'Ignoring'
          rules.ignore # It hasn't started yet
        when 1
          rules.label = 'Less than a day'
          rules.color = '#aaaaaa'
          rules.group_priority = 10 # Highest is top
        when 2..7
          rules.label = 'A week or less'
          rules.color = '#80bfff'
          rules.group_priority = 9
        when 8..14
          rules.label = 'Two weeks or less'
          rules.color = '#ffd700'
          rules.group_priority = 8
        when 15..28
          rules.label = 'Four weeks or less'
          rules.color = '#ce6300'
          rules.group_priority = 7
        when (29..)
          rules.label = 'More than four weeks'
          rules.color = '#990000'
          rules.group_priority = 6
        end
      end
    end
  end

  def run
    issue_rules_by_active_date = group_issues_by_active_dates
    possible_rules = select_possible_rules issue_rules_by_active_date

    data_sets = possible_rules.collect do |grouping_rule|
      make_data_set grouping_rule: grouping_rule, issue_rules_by_active_date: issue_rules_by_active_date
    end

    data_quality = scan_data_quality @issues

    wrap_and_render(binding, __FILE__)
  end

  def select_possible_rules issue_rules_by_active_date
    possible_rules = []
    issue_rules_by_active_date.each_pair do |_date, issues_rules_list|
      issues_rules_list.each do |_issue, rules|
        possible_rules << rules unless possible_rules.any? { |r| r.group == rules.group }
      end
    end
    possible_rules.sort_by!(&:group_priority)
  end

  # TODO: Replaces DailyChartItemGenerator
  def group_issues_by_active_dates
    hash = {}

    @issues.each do |issue|
      start = @cycletime.started_time(issue)&.to_date
      stop = @cycletime.stopped_time(issue)&.to_date
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
    positive = grouping_rule.group_priority.positive?

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
      backgroundColor: grouping_rule.color,
      borderColor: 'gray',
      borderWidth: grouping_rule.color == 'white' ? 1 : 0,
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
