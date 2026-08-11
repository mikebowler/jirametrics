# frozen_string_literal: true

require 'jirametrics/percentile_validation'

class GroupingRules < Rules
  include PercentileValidation

  attr_accessor :label, :issue_hint, :label_hint
  attr_reader :color, :last_day_of_period, :percentiles

  # nil means "inherit whatever the chart is configured with" and an empty list means "draw no
  # lines for this group", so neither is validated. Everything else gets the same treatment as
  # the chart level setter, because these numbers become JavaScript identifiers downstream and a
  # bad one takes the whole chart out with a syntax error.
  def percentiles= list
    @percentiles = list.nil? ? nil : validate_percentiles(list)
  end

  def last_day_of_period= value
    @last_day_of_period = value.is_a?(String) ? Date.parse(value) : value
  end

  def eql? other
    other.label == @label && other.color == @color
  end

  def group
    [@label, @color]
  end

  def color= color
    if color.is_a?(Array)
      raise ArgumentError, 'Color pair must have exactly two elements: [light_color, dark_color]' unless color.size == 2
      raise ArgumentError, 'Color pair elements must be strings' unless color.all?(String)

      if color.any? { |c| c.start_with?('--') }
        raise ArgumentError,
          'CSS variable references are not supported as color pair elements; use a literal color value instead'
      end

      light, dark = color
      @color = RawJavascript.new(
        "(document.documentElement.dataset.theme === 'dark' || " \
        '(!document.documentElement.dataset.theme && ' \
        "window.matchMedia('(prefers-color-scheme: dark)').matches)) " \
        "? #{dark.to_json} : #{light.to_json}"
      )
    else
      color = CssVariable[color] unless color.is_a?(CssVariable)
      @color = color
    end
  end
end
