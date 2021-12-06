# frozen_string_literal: true

module SelfOrIssueDispatcher
  def method_missing method_name, *args, &block
    raise "#{method_name} isn't a method on Issue or #{self.class}" unless ::Issue.method_defined? method_name.to_sym

    # Have to reference config outside the lambda so that it's accessible inside.
    # When the lambda is executed for real, it will be running inside the context of an Issue
    # object and at that point @config won't be referencing a variable from the right object.
    config = self

    ->(issue) do # rubocop:disable Style/Lambda
      parameters = issue.method(method_name.to_sym).parameters
      # Is the first parameter called config?
      if parameters.empty? == false && parameters[0][1] == :config
        new_args = [config] + args
        issue.__send__ method_name, *new_args, &block
      else
        issue.__send__ method_name, *args, &block
      end
    end
  end

  def respond_to_missing?(method_name, include_all = false)
    ::Issue.method_defined?(method_name.to_sym) || super
  end
end
