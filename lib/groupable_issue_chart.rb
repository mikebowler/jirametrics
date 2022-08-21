# frozen_string_literal: true

require './lib/rules'

module GroupableIssueChart
  class GroupingRules < Rules
    attr_accessor :label, :color

    def inspect
      "GroupingRules(label=#{label.inspect}, color=#{color}"
    end
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

    if user_provided_block
      instance_eval(&user_provided_block)
      return if @group_by_block
    end

    instance_eval(&default_block)
  end

  def grouping_rules &block
    @group_by_block = block
  end

  def group_issues completed_issues
    result = {}
    completed_issues.each do |issue|
      rules = GroupingRules.new
      @group_by_block.call(issue, rules)
      next if rules.ignored?

      (result[rules] ||= []) << issue
    end

    result.each_key do |rules|
      rules.color = "\##{Random.bytes(3).unpack1('H*')}" if rules.color.nil?
    end
    result
  end
end
