# frozen_string_literal: true

require 'digest'

class GroupingRules < Rules
  attr_accessor :label, :issue_hint
  attr_reader :color, :color_pair

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
      short_hash = Digest::SHA256.hexdigest("#{light}|#{dark}")[0, 8]
      @color_pair = { light: light, dark: dark }
      @color = CssVariable["--generated-color-#{short_hash}"]
    else
      color = CssVariable[color] unless color.is_a?(CssVariable)
      @color = color
      @color_pair = nil
    end
  end
end
