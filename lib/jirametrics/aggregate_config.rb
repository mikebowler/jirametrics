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

    if @included_projects.empty?
      raise "#{@project_config.name}: When aggregating, you must include at least one other project"
    end

    # If the date range wasn't set then calculate it now
    @project_config.time_range = find_time_range projects: @included_projects if @project_config.time_range.nil?

    adjust_issue_links
  end

  def adjust_issue_links
    issues = @project_config.issues
    issues.each do |issue|
      issue.issue_links.each do |link|
        other_issue_key = link.other_issue.key
        other_issue = issues.find { |i| i.key == other_issue_key }

        link.other_issue = other_issue if other_issue
      end
    end
  end

  def include_issues_from project_name
    project = @project_config.exporter.project_configs.find { |p| p.name == project_name }
    if project.nil?
      puts "Warning: Aggregated project #{@project_config.name.inspect} is attempting to load " \
        "project #{project_name.inspect} but it can't be found. Is it disabled?"
      return
    end

    @project_config.jira_url = project.jira_url if @project_config.jira_url.nil?
    unless @project_config.jira_url == project.jira_url
      raise 'Not allowed to aggregate projects from different Jira instances: ' \
        "#{@project_config.jira_url.inspect} and #{project.jira_url.inspect}"
    end

    @included_projects << project
    if project.file_configs.empty?
      issues = project.issues
    else
      issues = project.file_configs.first.issues
      if project.file_configs.size > 1
        puts 'More than one file section is defined. For the aggregated view, we always use ' \
          'the first file section'
      end
    end
    @project_config.add_issues issues
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
