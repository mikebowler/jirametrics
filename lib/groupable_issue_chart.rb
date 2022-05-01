# frozen_string_literal: true

require './lib/rules'

module GroupableIssueChart
  class GroupingRules < Rules
    attr_accessor :label, :color
  end

  def init_configuration_block user_provided_block, &default_block
    # The user provided a block but it's using the old deprecated style
    if user_provided_block && user_provided_block.arity == 1
      puts "DEPRECATED: #{self.class}: Use the new grouping_rules syntax"
      grouping_rules do |issue, rules|
        rules.label, rules.color = user_provided_block.call(issue)
      end
      return
    end

    if user_provided_block.nil?
      # The user didn't provide a block so we use the default one for the specific chart
      user_provided_block = default_block
    end

    instance_eval(&user_provided_block)
    raise 'If a configuration block is provided then grouping_rules must be set' if @group_by_block.nil?
  end

  def grouping_rules &block
    @group_by_block = block
  end

  def group_issues completed_issues
    raise '@group_by_block never got set' if @group_by_block.nil?

    result = {}
    completed_issues.each do |issue|
      rules = GroupingRules.new
      @group_by_block.call(issue, rules)
      next if rules.ignored?

      (result[rules] ||= []) << issue
    end
    result
  end
end
