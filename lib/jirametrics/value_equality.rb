# frozen_string_literal: true

# Perform an equality check based on whether the two objects have the same values
module ValueEquality
  def ==(other)
    return false unless other.class == self.class

    code = lambda do |object|
      names = object.instance_variables
      if object.respond_to? :value_equality_ignored_variables
        ignored_variables = object.value_equality_ignored_variables
        names.reject! { |n| ignored_variables.include? n.to_sym }
      end
      names.map { |variable| object.instance_variable_get variable }
    end

    code.call(self) == code.call(other)
  end

  def eql?(other)
    self == other
  end
end
