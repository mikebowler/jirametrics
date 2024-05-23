# frozen_string_literal: true

require 'date'

class AggregateConfig
  attr_reader :project_config, :included_projects

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

    # If the time range wasn't set then calculate it now
    @project_config.time_range = find_time_range projects: @included_projects if @project_config.time_range.nil?

    adjust_issue_links issues: @project_config.issues
  end

  # IssueLinks just have a reference to the key. Walk through all of them to see if we have a full
  # issue that we'd already loaded. If we do, then replace it.
  def adjust_issue_links issues:
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
      log "Warning: Aggregated project #{@project_config.name.inspect} is attempting to load " \
        "project #{project_name.inspect} but it can't be found. Is it disabled?"
      return
    end

    @project_config.jira_url = project.jira_url if @project_config.jira_url.nil?
    unless @project_config.jira_url == project.jira_url
      raise 'Not allowed to aggregate projects from different Jira instances: ' \
        "#{@project_config.jira_url.inspect} and #{project.jira_url.inspect}. For project #{project_name}"
    end

    @included_projects << project
    if project.file_configs.empty?
      issues = project.issues
    else
      issues = project.file_configs.first.issues
      if project.file_configs.size > 1
        log 'More than one file section is defined. For the aggregated view, we always use ' \
          'the first file section'
      end
    end
    @project_config.add_issues issues
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

    earliest..latest
  end

  private

  def log message
    @project_config.exporter.file_system.log message
  end
end
