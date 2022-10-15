# frozen_string_literal: true

require 'date'

class AggregateConfig
  attr_reader :project_config

  def initialize project_config:, block:
    @project_config = project_config
    @block = block

    @included_projects = []
  end

  def evaluate_next_level
    instance_eval(&@block)

    raise "#{@project}: When aggregating, you must include at least one other project" if @included_projects.empty?

    # If the date range wasn't set then calculate it now
    @project_config.time_range = find_time_range projects: @included_projects if @project_config.time_range.nil?
  end

  def include_issues_from project_name
    project = @project_config.exporter.project_configs.find { |p| p.name == project_name }
    raise "include_issues_from(#{project_name.inspect}) Can't find project with that name." if project.nil?

    @included_projects << project
    @project_config.add_issues project.issues
  end

  def date_range range
    @project_config.time_range = date_range_to_time_range(
      date_range: range, timezone_offset: project_config.exporter.timezone_offset
    )
  end

  def date_range_to_time_range date_range:, timezone_offset:
    start_of_first_day = Time.new(
      date_range.begin.year, date_range.begin.month, date_range.begin.day, 0, 0, 0, timezone_offset
    )
    end_of_last_day = Time.new(
      date_range.end.year, date_range.end.month, date_range.end.day, 23, 59, 59, timezone_offset
    )

    start_of_first_day..end_of_last_day
  end

  def find_time_range projects:
    raise "Can't calculate aggregated range as no projects were included." if projects.empty?

    earliest = nil
    latest = nil
    projects.each do |project|
      range = project.time_range
      earliest = range.begin if earliest.nil? || range.begin < earliest
      latest = range.end if latest.nil? || range.end > latest
    end

    raise "Can't calculate range" if earliest.nil? || latest.nil?
    earliest..latest
  end
end
