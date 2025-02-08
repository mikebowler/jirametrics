# frozen_string_literal: true

class CssVariable
  attr_reader :name

  def self.[](name)
    if name.is_a?(String) && name.start_with?('--')
      CssVariable.new name
    else
      name
    end
  end

  def initialize name
    @name = name
  end

  def to_json(*_args)
    "getComputedStyle(document.body).getPropertyValue('#{@name}')"
  end

  def to_s
    "var(#{@name})"
  end

  def inspect
    "CssVariable['#{@name}']"
  end

  def == other
    self.class == other.class && @name == other.name
  end
end
