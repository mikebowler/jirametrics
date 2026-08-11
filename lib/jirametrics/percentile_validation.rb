# frozen_string_literal: true

# Percentile lists arrive from two different places in the config DSL: the chart level
# "percentiles [50, 85]" setter and "rule.percentiles = [...]" inside a grouping_rules block.
# Both are user supplied and both end up as JavaScript annotation ids in the rendered chart, so
# both need the same guard rails. Including this module gives you a private validate_percentiles.
module PercentileValidation
  module_function

  # Returns the cleaned up list. Raises ArgumentError, naming the offending value, for anything
  # that isn't an Integer between 0 and 100.
  def validate_percentiles list
    list.each do |percentile|
      raise ArgumentError, "percentile #{percentile} must be an integer" unless percentile.is_a? Integer

      raise ArgumentError, "percentile #{percentile} must be between 0 and 100" unless percentile.between?(0, 100)
    end
    list.uniq.sort
  end

  # For the places where exactly one value is meaningful, such as a forecast that has to produce a
  # single number of days. Returns the value; raises the same errors as the list form.
  def validate_percentile value
    validate_percentiles([value]).first
  end
end
