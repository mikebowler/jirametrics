# frozen_string_literal: true

class GroupingRules < Rules
  attr_accessor :label
  attr_reader :color

  def eql? other
    other.label == @label && other.color == @color
  end

  def group
    [@label, @color]
  end

  def color= color
    color = CssVariable.new(color) if color.start_with?('--') && !color.is_a?(CssVariable)
    @color = color
  end
end
