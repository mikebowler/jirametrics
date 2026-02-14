# frozen_string_literal: true

require 'jirametrics/value_equality'

class BarChartRange
  include ValueEquality

  attr_accessor :start, :stop, :color, :title

  def initialize start:, stop:, color:, title:
    @start = start
    @stop = stop
    @color = color
    @title = title
  end
end
