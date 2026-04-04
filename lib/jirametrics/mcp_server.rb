# frozen_string_literal: true

require 'mcp'
require 'mcp/server/transports/stdio_transport'

class McpServer
  def initialize projects:, timezone_offset: '+00:00'
    @projects = projects
    @timezone_offset = timezone_offset
  end

  def run
    server = MCP::Server.new(
      name: 'jirametrics',
      version: Gem.loaded_specs['jirametrics']&.version&.to_s || '0.0.0',
      tools: [AgingWorkTool, CompletedWorkTool, NotYetStartedTool],
      server_context: { projects: @projects, timezone_offset: @timezone_offset }
    )

    transport = MCP::Server::Transports::StdioTransport.new(server)
    transport.open
  end

  HISTORY_FILTER_SCHEMA = {
    history_field: {
      type: 'string',
      description: 'When combined with history_value, only return issues where this field ever had that value ' \
                   '(e.g. "priority", "status"). Both history_field and history_value must be provided together.'
    },
    history_value: {
      type: 'string',
      description: 'The value to look for in the change history of history_field (e.g. "Highest", "Done").'
    },
    ever_blocked: {
      type: 'boolean',
      description: 'When true, only return issues that were ever blocked. Blocked includes flagged items, ' \
                   'issues in blocked statuses, and blocking issue links.'
    },
    ever_stalled: {
      type: 'boolean',
      description: 'When true, only return issues that were ever stalled. Stalled means the issue sat ' \
                   'inactive for longer than the stalled threshold, or entered a stalled status.'
    },
    currently_blocked: {
      type: 'boolean',
      description: 'When true, only return issues that are currently blocked (as of the data end date).'
    },
    currently_stalled: {
      type: 'boolean',
      description: 'When true, only return issues that are currently stalled (as of the data end date).'
    }
  }.freeze

  def self.flow_efficiency_percent issue, end_time
    active_time, total_time = issue.flow_efficiency_numbers(end_time: end_time)
    total_time.positive? ? (active_time / total_time * 100).round(1) : nil
  end

  def self.matches_blocked_stalled?(bsc, ever_blocked, ever_stalled, currently_blocked, currently_stalled)
    return false if ever_blocked && bsc.none?(&:blocked?)
    return false if ever_stalled && bsc.none?(&:stalled?)
    return false if currently_blocked && !bsc.last&.blocked?
    return false if currently_stalled && !bsc.last&.stalled?

    true
  end

  def self.matches_history?(issue, end_time, history_field, history_value,
                            ever_blocked, ever_stalled, currently_blocked, currently_stalled)
    return false if history_field && history_value &&
                    issue.changes.none? { |c| c.field == history_field && c.value == history_value }

    if ever_blocked || ever_stalled || currently_blocked || currently_stalled
      bsc = issue.blocked_stalled_changes(end_time: end_time)
      return false unless matches_blocked_stalled?(bsc, ever_blocked, ever_stalled,
                                                   currently_blocked, currently_stalled)
    end

    true
  end

  class AgingWorkTool < MCP::Tool
    tool_name 'aging_work'
    description 'Returns all issues that have been started but not yet completed (work in progress), ' \
                'sorted from oldest to newest. Age is the number of days since the issue was started.'

    input_schema(
      type: 'object',
      properties: {
        min_age_days: {
          type: 'integer',
          description: 'Only return issues at least this many days old. Omit to return all ages.'
        },
        project: {
          type: 'string',
          description: 'Only return issues from this project name. Omit to return all projects.'
        },
        **HISTORY_FILTER_SCHEMA
      }
    )

    def self.call(server_context:, min_age_days: nil, project: nil,
                  history_field: nil, history_value: nil, ever_blocked: nil, ever_stalled: nil,
                  currently_blocked: nil, currently_stalled: nil)
      rows = []

      server_context[:projects].each do |project_name, project_data|
        next if project && project_name != project

        today = project_data[:today]
        project_data[:issues].each do |issue|
          started, stopped = issue.started_stopped_times
          next unless started && !stopped

          age = (today - started.to_date).to_i + 1
          next if min_age_days && age < min_age_days
          unless McpServer.matches_history?(issue, project_data[:end_time],
                                            history_field, history_value, ever_blocked, ever_stalled,
                                            currently_blocked, currently_stalled)
            next
          end

          rows << {
            key: issue.key,
            summary: issue.summary,
            status: issue.status.name,
            type: issue.type,
            age_days: age,
            flow_efficiency: McpServer.flow_efficiency_percent(issue, project_data[:end_time]),
            project: project_name
          }
        end
      end

      rows.sort_by! { |r| -r[:age_days] }

      if rows.empty?
        text = 'No aging work found.'
      else
        lines = rows.map do |r|
          fe = r[:flow_efficiency] ? " | FE: #{r[:flow_efficiency]}%" : ''
          "#{r[:key]} | #{r[:project]} | #{r[:type]} | #{r[:status]} | Age: #{r[:age_days]}d#{fe} | #{r[:summary]}"
        end
        text = lines.join("\n")
      end

      MCP::Tool::Response.new([{ type: 'text', text: text }])
    end
  end

  class CompletedWorkTool < MCP::Tool
    tool_name 'completed_work'
    description 'Returns issues that have been completed, sorted most recently completed first. ' \
                'Includes cycle time (days from start to completion).'

    input_schema(
      type: 'object',
      properties: {
        days_back: {
          type: 'integer',
          description: 'Only return issues completed within this many days of the data end date. Omit to return all.'
        },
        project: {
          type: 'string',
          description: 'Only return issues from this project name. Omit to return all projects.'
        },
        completed_status: {
          type: 'string',
          description: 'Only return issues whose status at completion matches this value (e.g. "Cancelled", "Done").'
        },
        completed_resolution: {
          type: 'string',
          description: 'Only return issues whose resolution at completion matches this value (e.g. "Won\'t Do").'
        },
        **HISTORY_FILTER_SCHEMA
      }
    )

    def self.build_row issue, project_name, started, stopped, cutoff, completed_status, completed_resolution,
                       end_time, history_field, history_value, ever_blocked, ever_stalled,
                       currently_blocked, currently_stalled
      completed_date = stopped.to_date
      return nil if cutoff && completed_date < cutoff

      status_at_done, resolution_at_done = issue.status_resolution_at_done
      return nil if completed_status && status_at_done&.name != completed_status
      return nil if completed_resolution && completed_resolution != resolution_at_done
      return nil unless McpServer.matches_history?(issue, end_time,
                                                   history_field, history_value, ever_blocked, ever_stalled,
                                                   currently_blocked, currently_stalled)

      cycle_time = started ? (completed_date - started.to_date).to_i + 1 : nil
      {
        key: issue.key,
        summary: issue.summary,
        type: issue.type,
        completed_date: completed_date,
        cycle_time_days: cycle_time,
        flow_efficiency: McpServer.flow_efficiency_percent(issue, stopped),
        status_at_done: status_at_done&.name,
        resolution_at_done: resolution_at_done,
        project: project_name
      }
    end

    def self.call(server_context:, days_back: nil, project: nil,
                  completed_status: nil, completed_resolution: nil,
                  history_field: nil, history_value: nil, ever_blocked: nil, ever_stalled: nil,
                  currently_blocked: nil, currently_stalled: nil)
      rows = []

      server_context[:projects].each do |project_name, project_data|
        next if project && project_name != project

        today = project_data[:today]
        cutoff = today - days_back if days_back

        project_data[:issues].each do |issue|
          started, stopped = issue.started_stopped_times
          next unless stopped

          row = build_row(issue, project_name, started, stopped, cutoff, completed_status, completed_resolution,
                          project_data[:end_time], history_field, history_value, ever_blocked, ever_stalled,
                          currently_blocked, currently_stalled)
          rows << row if row
        end
      end

      rows.sort_by! { |r| -r[:completed_date].to_time.to_i }

      if rows.empty?
        text = 'No completed work found.'
      else
        lines = rows.map do |r|
          ct = r[:cycle_time_days] ? "#{r[:cycle_time_days]}d" : 'unknown'
          fe = r[:flow_efficiency] ? " | FE: #{r[:flow_efficiency]}%" : ''
          completion = [r[:status_at_done], r[:resolution_at_done]].compact.join(' / ')
          "#{r[:key]} | #{r[:project]} | #{r[:type]} | #{r[:completed_date]} | " \
            "Cycle time: #{ct}#{fe} | #{completion} | #{r[:summary]}"
        end
        text = lines.join("\n")
      end

      MCP::Tool::Response.new([{ type: 'text', text: text }])
    end
  end

  class NotYetStartedTool < MCP::Tool
    tool_name 'not_yet_started'
    description 'Returns issues that have not yet been started (backlog items), sorted by creation date oldest first.'

    input_schema(
      type: 'object',
      properties: {
        project: {
          type: 'string',
          description: 'Only return issues from this project name. Omit to return all projects.'
        },
        **HISTORY_FILTER_SCHEMA
      }
    )

    def self.call(server_context:, project: nil,
                  history_field: nil, history_value: nil, ever_blocked: nil, ever_stalled: nil,
                  currently_blocked: nil, currently_stalled: nil)
      rows = []

      server_context[:projects].each do |project_name, project_data|
        next if project && project_name != project

        project_data[:issues].each do |issue|
          started, stopped = issue.started_stopped_times
          next if started || stopped
          unless McpServer.matches_history?(issue, project_data[:end_time],
                                            history_field, history_value, ever_blocked, ever_stalled,
                                            currently_blocked, currently_stalled)
            next
          end

          rows << {
            key: issue.key,
            summary: issue.summary,
            status: issue.status.name,
            type: issue.type,
            created: issue.created.to_date,
            project: project_name
          }
        end
      end

      rows.sort_by! { |r| r[:created] }

      if rows.empty?
        text = 'No unstarted work found.'
      else
        lines = rows.map do |r|
          "#{r[:key]} | #{r[:project]} | #{r[:type]} | #{r[:status]} | Created: #{r[:created]} | #{r[:summary]}"
        end
        text = lines.join("\n")
      end

      MCP::Tool::Response.new([{ type: 'text', text: text }])
    end
  end
end
