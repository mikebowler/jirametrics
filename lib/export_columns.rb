# frozen_string_literal: true

class ExportColumns 
  attr_reader :columns

  def initialize file:, block:
    @columns = []
    @file = file
    @block = block
  end

  def run
    instance_eval(&@block)
  end

  def write_headers *arg
    @write_headers = arg[0] unless arg.empty?
    @write_headers
  end

  def date label, proc
    @columns << [:date, label, proc]
  end

  def string label, proc
    @columns << [:string, label, proc]
  end

  def column_entry_times
    board_columns = @file.project.board_columns
    raise 'Did you set a board_id? Unable to find configuration.' if board_columns.nil?

    board_columns.each do |column|
      date column.name, first_time_in_status(*column.status_ids)
    end
  end

  def method_missing method_name, *args, &block
    raise "#{method_name} isn't a method on Issue or ExportColumns" unless ::Issue.method_defined? method_name.to_sym

    # Have to reference config outside the lambda so that it's accessible inside.
    # When the lambda is executed for real, it will be running inside the context of an Issue
    # object and at that point @config won't be referencing a variable from the right object.
    config = self
    puts "self=#{self.class}"

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

  def respond_to_missing?(method_name, include_private = false)
    ::Issue.method_defined?(method_name.to_sym) || super
  end
end
