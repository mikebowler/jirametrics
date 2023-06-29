# frozen_string_literal: true

class TrendLineCalculator
  # Using math from https://math.stackexchange.com/questions/204020/what-is-the-equation-used-to-calculate-a-linear-trendline

  def initialize points
    # We can't do trend calculations with less than two data points
    @valid = points.size >= 2
    return unless valid?

    sum_of_x = points.collect { |x, _y| x }.sum
    sum_of_y = points.collect { |_x, y| y }.sum
    sum_of_xy = points.collect { |x, y| x * y }.sum
    sum_of_x2 = points.collect { |x, _y| x * x }.sum
    n = points.size.to_f

    @slope = ((n * sum_of_xy) - (sum_of_x * sum_of_y)) / ((n * sum_of_x2) - (sum_of_x * sum_of_x))
    @offset = (sum_of_y - (@slope * sum_of_x)) / n

    @valid = false if vertical?
  end

  def valid? = @valid
  def horizontal? = @slope.zero?
  def vertical? = @slope.nan? || @slope.infinite?

  def calc_y x: # rubocop:disable Naming/MethodParameterName
    ((x * @slope) + @offset).to_i
  end

  def line_crosses_at y: # rubocop:disable Naming/MethodParameterName
    raise "line will never cross #{y}. Trend is perfectly horizontal" if horizontal?

    ((y.to_f - @offset) / @slope).to_i
  end

  # If the trend line can't be calculated then return an empty array. Otherwise, return
  # an array with two (x,y) points, with which you can draw the trend line.
  def chart_datapoints range:, max_y:, min_y: 0
    raise 'max_y is nil' if max_y.nil?
    return [] unless valid?

    data_points = []
    x_start = range.begin
    y_start = calc_y(x: range.begin).to_i
    x_end = range.end
    y_end = calc_y(x: range.end).to_i

    if y_start < min_y
      x_start = line_crosses_at y: 0
      y_start = 0
    end

    if y_start > max_y
      x_start = line_crosses_at y: max_y
      y_start = max_y
    end

    if y_end < min_y
      x_end = line_crosses_at y: 0
      y_end = 0
    end

    if y_end > max_y
      x_end = line_crosses_at y: max_y
      y_end = max_y
    end

    data_points << { x: x_start, y: y_start }
    data_points << { x: x_end, y: y_end }

    data_points
  end
end
