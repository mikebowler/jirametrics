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
  end

  def valid? = @valid
  def horizontal? = @slope.zero?

  def calc_y x: # rubocop:disable Naming/MethodParameterName
    (x * @slope) + @offset
  end

  def calc_x_where_y_is_zero
    raise 'y will never be zero. Trend is perfectly horizontal' if horizontal?

    -(@offset / @slope)
  end

  # If the trend line can't be calculated then return an empty array. Otherwise, return
  # an array with two (x,y) points, with which you can draw the trend line.
  def chart_datapoints range:
    data_points = []
    if valid?
      x_start = range.begin
      y_start = calc_y(x: range.begin).to_i
      x_end = range.end
      y_end = calc_y(x: range.end).to_i

      if y_start.negative?
        x_start = calc_x_where_y_is_zero.to_i
        y_start = 0
      end

      if y_end.negative?
        x_end = calc_x_where_y_is_zero.to_i
        y_end = 0
      end

      data_points << { x: x_start, y: y_start }
      data_points << { x: x_end, y: y_end }
    end
    data_points
  end
end
