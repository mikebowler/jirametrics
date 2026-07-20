# frozen_string_literal: true

class Rules
  # Boolean positional is the config-block DSL's public API (ignore false).
  def ignore value = true # rubocop:disable Style/OptionalBooleanParameter
    @ignore = value
  end

  def ignored?
    @ignore == true
  end

  def hash
    2 # TODO: While this works, it's not performant
  end
end
