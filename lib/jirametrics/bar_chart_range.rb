# frozen_string_literal: true

require 'jirametrics/value_equality'

class BarChartRange
  include ValueEquality

  attr_accessor :start, :stop, :color, :title, :highlight

  def initialize start:, stop:, color:, title:, highlight: false
    @start = start
    @stop = stop
    @color = color
    @title = title
    @highlight = highlight
  end
end
