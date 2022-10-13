# frozen_string_literal: true

require 'date'

class AggregateConfig
  attr_reader :project_config

  def initialize project_config:, block:
    @project_config = project_config
    @block = block
  end

  def evaluate_next_level
    instance_eval(&@block)
  end

  def include_issues_from project_name
    project = @project_config.exporter.project_configs.find { |p| p.name == project_name }
    raise "include_issues_from(#{project_name.inspect}) Can't find project with that name." if project.nil?

    @project_config.add_issues project.issues
  end

  def date_range range
    start_of_first_day = Time.new(range.begin.year, range.begin.month, range.begin.day, 0, 0, 0, @timezone_offset)
    end_of_last_day = Time.new(range.end.year, range.end.month, range.end.day, 23, 59, 59, @timezone_offset)

    @project_config.time_range = start_of_first_day..end_of_last_day
  end
end
