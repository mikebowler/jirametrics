# frozen_string_literal: true

require 'jirametrics/rules'
require 'jirametrics/grouping_rules'

module GroupableIssueChart
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
    completed_issues.each do |issue|
      rules = GroupingRules.new
      @group_by_block.call(issue, rules)
      if rules.ignored?
        ignored_issues << issue
        next
      end

      (result[rules] ||= []) << issue
    end

    completed_issues.reject! { |issue| ignored_issues.include? issue }

    result.each_key do |rules|
      rules.color = random_color if rules.color.nil?
    end
    result
  end
end
