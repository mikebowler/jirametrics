# frozen_string_literal: true

class TrendLineCalculator
  # Using math from https://math.stackexchange.com/questions/204020/what-is-the-equation-used-to-calculate-a-linear-trendline

  def initialize points
    sum_of_x = points.collect { |x, _y| x }.sum
    sum_of_y = points.collect { |_x, y| y }.sum
    sum_of_xy = points.collect { |x, y| x * y }.sum
    sum_of_x2 = points.collect { |x, _y| x * x }.sum
    n = points.size.to_f

    @slope = ((n * sum_of_xy) - (sum_of_x * sum_of_y)) / ((n * sum_of_x2) - (sum_of_x * sum_of_x))
    @offset = (sum_of_y - (@slope * sum_of_x)) / n
  end

  def calc_y x: # rubocop:disable Naming/MethodParameterName
    (x * @slope) + @offset
  end

  def calc_x_where_y_is_zero
    return 0 if @slope.zero?

    -(@offset / @slope)
  end
end
