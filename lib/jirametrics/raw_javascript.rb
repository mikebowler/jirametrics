# frozen_string_literal: true

# When strings are serialized into JSON, they're converted to actual strings. The purpose
# of this class is to allow raw javascript to be passed through.
class RawJavascript
  def initialize content
    @content = content
  end

  def to_json(*_args)
    @content
  end
end
