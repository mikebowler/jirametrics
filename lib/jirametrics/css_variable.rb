# frozen_string_literal: true

class CssVariable < String
  def initialize name
    super
    @name = name
  end

  def to_json(*_args)
    "getComputedStyle(document.body).getPropertyValue('#{@name}')"
  end
end
