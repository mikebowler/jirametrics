# frozen_string_literal: true

class GroupingRules < Rules
  attr_accessor :label, :color

  def eql? other
    other.label == @label && other.color == @color
  end

  def group
    [@label, @color]
  end
end
