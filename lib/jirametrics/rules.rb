# frozen_string_literal: true

class Rules
  def ignore
    @ignore = true
  end

  def ignored?
    @ignore == true
  end

  def hash
    2 # TODO: While this works, it's not performant
  end
end
