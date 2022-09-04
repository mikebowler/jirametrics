# frozen_string_literal: true

class GroupingRules < Rules
  attr_accessor :label, :color

  def inspect
    "GroupingRules(label=#{label.inspect}, color=#{color}"
  end
end
