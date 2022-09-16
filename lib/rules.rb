# frozen_string_literal: true

class Rules
  def ignore
    @ignore = true
  end

  def ignored?
    @ignore == true
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

  def inspect
    result = String.new
    result << "#{self.class}("
    result << instance_variables.collect do |variable|
      "#{variable}=#{instance_variable_get(variable).inspect}"
    end.join(', ')
    result << ')'
    result
  end

end
