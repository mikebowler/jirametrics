# frozen_string_literal: true

class GroupingRules < Rules
  attr_accessor :label, :issue_hint
  attr_reader :color

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
