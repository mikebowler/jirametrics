# frozen_string_literal: true

class Rules
  def ignore
    @ignore = true
  end

  def ignored?
    @ignore
  end

  def eql?(other)
    (other.class == self.class) && (other.state == state)
  end

  def state
    instance_variables.map { |variable| instance_variable_get variable }
  end

  def hash
    2 # TODO: While this work, it's not performant
  end
end
