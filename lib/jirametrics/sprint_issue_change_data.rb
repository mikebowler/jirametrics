# frozen_string_literal: true

require 'jirametrics/value_equality'

class SprintIssueChangeData
  include ValueEquality
  attr_reader :time, :action, :value, :issue, :estimate

  def initialize time:, action:, value:, issue:, estimate:
    @time = time
    @action = action
    @value = value
    @issue = issue
    @estimate = estimate
  end

  def inspect
    result = +''
    result << 'SprintIssueChangeData('
    result << instance_variables.collect do |variable|
      "#{variable}=#{instance_variable_get(variable).inspect}"
    end.sort.join(', ')
    result << ')'
    result
  end
end
