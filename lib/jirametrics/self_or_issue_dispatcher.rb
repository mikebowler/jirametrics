# frozen_string_literal: true

module SelfOrIssueDispatcher
  def method_missing method_name, *args, &block
    raise "#{method_name} isn't a method on Issue or #{self.class}" unless ::Issue.method_defined? method_name.to_sym

    ->(issue) do # rubocop:disable Style/Lambda
      issue.__send__ method_name, *args, &block
    end
  end

  def respond_to_missing?(method_name, include_all = false)
    ::Issue.method_defined?(method_name.to_sym) || super
  end
end
