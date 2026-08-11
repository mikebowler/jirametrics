# frozen_string_literal: true

require 'jirametrics/rules'
require 'jirametrics/grouping_rules'

module GroupableIssueChart
  attr_accessor :issue_hints, :issue_periods
  attr_reader :group_by_block

  def init_configuration_block user_provided_block, &default_block
    instance_eval(&user_provided_block)
    instance_eval(&default_block) unless @group_by_block
  end

  def grouping_rules &block
    @group_by_block = block
  end

  def group_issues completed_issues
    result = {}
    ignored_issues = []
    @issue_hints = {}
    @issue_periods = {}
    completed_issues.each do |issue|
      rules = GroupingRules.new
      @group_by_block.call(issue, rules)
      if rules.ignored?
        ignored_issues << issue
        next
      end

      @issue_hints[issue] = rules.issue_hint
      @issue_periods[issue] = rules.last_day_of_period
      accumulate_issue_for_group result, rules, issue
    end

    completed_issues.reject! { |issue| ignored_issues.include? issue }

    result.each_key do |rules|
      rules.color = random_color if rules.color.nil?
    end
    result
  end

  # Ruby's Hash keeps whichever key object it saw first, so a later issue whose rules object
  # has different percentiles needs to be reconciled against that retained key rather than
  # just appended under its own (discarded) key.
  def accumulate_issue_for_group result, rules, issue
    existing_key = result.keys.find { |key| key.eql? rules }
    reconcile_percentiles existing_key, rules if existing_key
    (result[existing_key || rules] ||= []) << issue
  end

  # The retained hash key is whichever rules object arrived first, so a later issue setting a
  # different list would silently lose. That can only be a config error, so say so.
  def reconcile_percentiles existing_key, rules
    incoming = rules.percentiles
    return if incoming.nil?

    existing = existing_key.percentiles
    if existing.nil?
      existing_key.percentiles = incoming
    elsif existing != incoming
      raise ArgumentError,
        "group #{existing_key.label.inspect} was given conflicting percentiles: " \
        "#{existing.inspect} and #{incoming.inspect}"
    end
  end
end
