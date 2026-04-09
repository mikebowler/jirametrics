# frozen_string_literal: true

require 'mcp'
require 'mcp/server/transports/stdio_transport'

class McpServer
  def initialize projects:, aggregates: {}, timezone_offset: '+00:00'
    @projects = projects
    @aggregates = aggregates
    @timezone_offset = timezone_offset
  end

  def run
    canonical_tools = [ListProjectsTool, AgingWorkTool, CompletedWorkTool, NotYetStartedTool, StatusTimeAnalysisTool]
    alias_tools = ALIASES.map do |alias_name, canonical|
      schema = canonical.input_schema
      Class.new(canonical) do
        tool_name alias_name
        input_schema schema
      end
    end

    server = MCP::Server.new(
      name: 'jirametrics',
      version: Gem.loaded_specs['jirametrics']&.version&.to_s || '0.0.0',
      tools: canonical_tools + alias_tools,
      server_context: { projects: @projects, aggregates: @aggregates, timezone_offset: @timezone_offset }
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

  def self.resolve_projects server_context, project_filter
    return nil if project_filter.nil?

    aggregates = server_context[:aggregates] || {}
    aggregates[project_filter] || [project_filter]
  end

  def self.column_name_for board, status_id
    board.visible_columns.find { |c| c.status_ids.include?(status_id) }&.name
  end

  def self.time_per_column issue, end_time
    changes = issue.status_changes
    _, stopped = issue.started_stopped_times
    effective_end = stopped && stopped < end_time ? stopped : end_time
    board = issue.board

    result = Hash.new(0.0)

    if changes.empty?
      col = column_name_for(board, issue.status.id) || issue.status.name
      duration = effective_end - issue.created
      result[col] += duration if duration.positive?
      return result
    end

    first_change = changes.first
    initial_col = column_name_for(board, first_change.old_value_id) || first_change.old_value
    initial_duration = first_change.time - issue.created
    result[initial_col] += initial_duration if initial_duration.positive?

    changes.each_cons(2) do |prev_change, next_change|
      col = column_name_for(board, prev_change.value_id) || prev_change.value
      duration = next_change.time - prev_change.time
      result[col] += duration if duration.positive?
    end

    last_change = changes.last
    final_col = column_name_for(board, last_change.value_id) || last_change.value
    final_duration = effective_end - last_change.time
    result[final_col] += final_duration if final_duration.positive?

    result
  end

  def self.time_per_status issue, end_time
    changes = issue.status_changes
    _, stopped = issue.started_stopped_times
    effective_end = stopped && stopped < end_time ? stopped : end_time

    result = Hash.new(0.0)

    if changes.empty?
      duration = effective_end - issue.created
      result[issue.status.name] += duration if duration.positive?
      return result
    end

    first_change = changes.first
    initial_duration = first_change.time - issue.created
    result[first_change.old_value] += initial_duration if initial_duration.positive?

    changes.each_cons(2) do |prev_change, next_change|
      duration = next_change.time - prev_change.time
      result[prev_change.value] += duration if duration.positive?
    end

    last_change = changes.last
    final_duration = effective_end - last_change.time
    result[last_change.value] += final_duration if final_duration.positive?

    result
  end

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

  class ListProjectsTool < MCP::Tool
    tool_name 'list_projects'
    description 'Lists all available projects with basic metadata. Call this first when the user asks a ' \
                'question that could apply to multiple projects, so you can clarify which one they mean.'

    input_schema(type: 'object', properties: {})

    def self.call(server_context:, **)
      lines = server_context[:projects].map do |project_name, project_data|
        "#{project_name} | #{project_data[:issues].size} issues | Data through: #{project_data[:today]}"
      end

      aggregates = server_context[:aggregates] || {}
      unless aggregates.empty?
        lines << ''
        lines << 'Aggregate groups (can be used as a project filter):'
        aggregates.each do |name, constituent_names|
          lines << "#{name} | includes: #{constituent_names.join(', ')}"
        end
      end

      MCP::Tool::Response.new([{ type: 'text', text: lines.join("\n") }])
    end
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
        current_status: {
          type: 'string',
          description: 'Only return issues currently in this status (e.g. "Review", "In Progress").'
        },
        current_column: {
          type: 'string',
          description: 'Only return issues whose current status maps to this board column (e.g. "In Progress").'
        },
        **HISTORY_FILTER_SCHEMA
      }
    )

    def self.call(server_context:, min_age_days: nil, project: nil, project_name: nil,
                  current_status: nil, current_column: nil,
                  history_field: nil, history_value: nil, ever_blocked: nil, ever_stalled: nil,
                  currently_blocked: nil, currently_stalled: nil, **)
      project ||= project_name
      rows = []
      allowed_projects = McpServer.resolve_projects(server_context, project)

      server_context[:projects].each do |project_name, project_data|
        next if allowed_projects && !allowed_projects.include?(project_name)

        today = project_data[:today]
        project_data[:issues].each do |issue|
          started, stopped = issue.started_stopped_times
          next unless started && !stopped
          next if current_status && issue.status.name != current_status
          next if current_column && McpServer.column_name_for(issue.board, issue.status.id) != current_column

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

    def self.call(server_context:, days_back: nil, project: nil, project_name: nil,
                  completed_status: nil, completed_resolution: nil,
                  history_field: nil, history_value: nil, ever_blocked: nil, ever_stalled: nil,
                  currently_blocked: nil, currently_stalled: nil, **)
      project ||= project_name
      rows = []
      allowed_projects = McpServer.resolve_projects(server_context, project)

      server_context[:projects].each do |project_name, project_data|
        next if allowed_projects && !allowed_projects.include?(project_name)

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
        current_status: {
          type: 'string',
          description: 'Only return issues currently in this status (e.g. "To Do", "Backlog").'
        },
        current_column: {
          type: 'string',
          description: 'Only return issues whose current status maps to this board column.'
        },
        **HISTORY_FILTER_SCHEMA
      }
    )

    def self.call(server_context:, project: nil, project_name: nil, current_status: nil, current_column: nil,
                  history_field: nil, history_value: nil, ever_blocked: nil, ever_stalled: nil,
                  currently_blocked: nil, currently_stalled: nil, **)
      project ||= project_name
      rows = []
      allowed_projects = McpServer.resolve_projects(server_context, project)

      server_context[:projects].each do |project_name, project_data|
        next if allowed_projects && !allowed_projects.include?(project_name)

        project_data[:issues].each do |issue|
          started, stopped = issue.started_stopped_times
          next if started || stopped
          next if current_status && issue.status.name != current_status
          next if current_column && McpServer.column_name_for(issue.board, issue.status.id) != current_column
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

  class StatusTimeAnalysisTool < MCP::Tool
    tool_name 'status_time_analysis'
    description 'Aggregates the time issues spend in each status or column, ranked by average days. ' \
                'Useful for identifying bottlenecks. Before calling this tool, always ask the user ' \
                'which issues they want to include: aging (in progress), completed, not yet started, ' \
                'or all. Do not assume — the answer changes the result significantly.'

    input_schema(
      type: 'object',
      properties: {
        project: {
          type: 'string',
          description: 'Only include issues from this project name. Omit to include all projects.'
        },
        issue_state: {
          type: 'string',
          enum: %w[all aging completed not_started],
          description: 'Which issues to include: "aging" (in progress), "completed", ' \
                       '"not_started" (backlog), or "all" (default).'
        },
        group_by: {
          type: 'string',
          enum: %w[status column],
          description: 'Whether to group results by status name (default) or board column.'
        }
      }
    )

    def self.select_issues issue, issue_state
      started, stopped = issue.started_stopped_times
      case issue_state
      when 'aging' then started && !stopped
      when 'completed' then !!stopped
      when 'not_started' then !started && !stopped
      else true
      end
    end

    def self.call(server_context:, project: nil, project_name: nil, issue_state: 'all', group_by: 'status',
                  column: nil, **)
      project ||= project_name
      group_by = 'column' if column

      totals = Hash.new { |h, k| h[k] = { total_seconds: 0.0, visit_count: 0 } }
      allowed_projects = McpServer.resolve_projects(server_context, project)

      server_context[:projects].each do |project_name, project_data|
        next if allowed_projects && !allowed_projects.include?(project_name)

        project_data[:issues].each do |issue|
          next unless select_issues(issue, issue_state)

          time_map = if group_by == 'column'
                       McpServer.time_per_column(issue, project_data[:end_time])
                     else
                       McpServer.time_per_status(issue, project_data[:end_time])
                     end

          time_map.each do |name, seconds|
            totals[name][:total_seconds] += seconds
            totals[name][:visit_count] += 1
          end
        end
      end

      return MCP::Tool::Response.new([{ type: 'text', text: 'No data found.' }]) if totals.empty?

      rows = totals.map do |name, data|
        total_days = (data[:total_seconds] / 86_400.0).round(1)
        avg_days = (data[:total_seconds] / data[:visit_count] / 86_400.0).round(1)
        { name: name, total_days: total_days, avg_days: avg_days, visit_count: data[:visit_count] }
      end
      rows.sort_by! { |r| -r[:avg_days] }

      label = group_by == 'column' ? 'Column' : 'Status'
      lines = rows.map do |r|
        "#{label}: #{r[:name]} | Avg: #{r[:avg_days]}d | Total: #{r[:total_days]}d | Issues: #{r[:visit_count]}"
      end
      MCP::Tool::Response.new([{ type: 'text', text: lines.join("\n") }])
    end
  end

  # Alternative tool names used by AI agents other than Claude.
  # Each entry maps an alias name to the canonical tool class it delegates to.
  # The alias inherits the canonical tool's schema and call behaviour automatically.
  # To add a new alias, append one line: 'alias_name' => CanonicalToolClass
  ALIASES = {
    'board_list' => ListProjectsTool
  }.freeze
end
