# frozen_string_literal: true

require 'mcp'
require 'mcp/server/transports/stdio_transport'
require 'json-schema'
# Suppress the MultiJSON deprecation warning. json-schema enables MultiJSON by default if the
# gem is present anywhere in the environment, but we don't use it.
JSON::Validator.use_multi_json = false

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

  # Bundles the six history + blocked/stalled query parameters that every tool accepts, so they travel
  # as one argument instead of a six-long positional tail through matches_history? and the handlers.
  HistoryFilter = Data.define(
    :history_field, :history_value, :ever_blocked, :ever_stalled, :currently_blocked, :currently_stalled
  ) do
    def self.from(history_field: nil, history_value: nil, ever_blocked: nil, ever_stalled: nil,
                  currently_blocked: nil, currently_stalled: nil, **)
      new(
        history_field: history_field, history_value: history_value,
        ever_blocked: ever_blocked, ever_stalled: ever_stalled,
        currently_blocked: currently_blocked, currently_stalled: currently_stalled
      )
    end

    def history? = !!(history_field && history_value)

    def blocked_stalled? = !!(ever_blocked || ever_stalled || currently_blocked || currently_stalled)

    def matches_change?(changes) = changes.any? { |c| c.field == history_field && c.value == history_value }
  end

  def self.resolve_projects server_context, project_filter
    return nil if project_filter.nil?

    aggregates = server_context[:aggregates] || {}
    aggregates[project_filter] || [project_filter]
  end

  def self.column_name_for board, status_id
    board.visible_columns.find { |c| c.status_ids.include?(status_id) }&.name
  end

  # The shared iteration spine of every query tool: resolve the project filter, skip disallowed projects,
  # and yield each surviving issue with its project name and data.
  def self.each_allowed_issue server_context, project
    allowed_projects = resolve_projects(server_context, project)
    server_context[:projects].each do |project_name, project_data|
      next if allowed_projects && !allowed_projects.include?(project_name)

      project_data[:issues].each do |issue|
        yield issue, project_name, project_data
      end
    end
  end

  # Collects the non-nil rows a block returns for each allowed issue (the row-oriented tools).
  def self.collect_rows server_context, project
    rows = []
    each_allowed_issue(server_context, project) do |issue, project_name, project_data|
      row = yield issue, project_name, project_data
      rows << row if row
    end
    rows
  end

  # Renders already-sorted rows as a text Response: the empty-message when there are none, otherwise
  # each row formatted by the block and newline-joined.
  def self.render_rows rows, empty:, &block
    text = rows.empty? ? empty : rows.map(&block).join("\n")
    MCP::Tool::Response.new([{ type: 'text', text: text }])
  end

  # Shared current-state filter for the aging and not-yet-started tools.
  def self.matches_current_state? issue, current_status, current_column
    return false if current_status && issue.status.name != current_status
    return false if current_column && column_name_for(issue.board, issue.status.id) != current_column

    true
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

  def self.matches_blocked?(bsc, filter)
    return false if filter.ever_blocked && bsc.none?(&:blocked?)
    return false if filter.currently_blocked && !bsc.last&.blocked?

    true
  end

  def self.matches_stalled?(bsc, filter)
    return false if filter.ever_stalled && bsc.none?(&:stalled?)
    return false if filter.currently_stalled && !bsc.last&.stalled?

    true
  end

  def self.matches_blocked_stalled?(bsc, filter)
    matches_blocked?(bsc, filter) && matches_stalled?(bsc, filter)
  end

  def self.matches_history?(issue, end_time, filter)
    return false if filter.history? && !filter.matches_change?(issue.changes)
    return false if filter.blocked_stalled? &&
                    !matches_blocked_stalled?(issue.blocked_stalled_changes(end_time: end_time), filter)

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
                  current_status: nil, current_column: nil, **history_args)
      project ||= project_name
      filter = McpServer::HistoryFilter.from(**history_args)

      rows = McpServer.collect_rows(server_context, project) do |issue, name, project_data|
        build_row(issue, name, project_data, min_age_days, current_status, current_column, filter)
      end
      rows.sort_by! { |r| -r[:age_days] }

      McpServer.render_rows(rows, empty: 'No aging work found.') { |r| format_line(r) }
    end

    def self.build_row issue, project_name, project_data, min_age_days, current_status, current_column, filter
      started, stopped = issue.started_stopped_times
      return nil unless started && !stopped
      return nil unless McpServer.matches_current_state?(issue, current_status, current_column)

      age = (project_data[:today] - started.to_date).to_i + 1
      return nil if min_age_days && age < min_age_days
      return nil unless McpServer.matches_history?(issue, project_data[:end_time], filter)

      {
        key: issue.key,
        summary: issue.summary,
        status: issue.status.name,
        type: issue.type,
        age_days: age,
        flow_efficiency: McpServer.flow_efficiency_percent(issue, project_data[:end_time]),
        project: project_name
      }
    end

    def self.format_line row
      fe = row[:flow_efficiency] ? " | FE: #{row[:flow_efficiency]}%" : ''
      "#{row[:key]} | #{row[:project]} | #{row[:type]} | #{row[:status]} | " \
        "Age: #{row[:age_days]}d#{fe} | #{row[:summary]}"
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

    def self.call(server_context:, days_back: nil, project: nil, project_name: nil,
                  completed_status: nil, completed_resolution: nil, **history_args)
      project ||= project_name
      filter = McpServer::HistoryFilter.from(**history_args)

      rows = McpServer.collect_rows(server_context, project) do |issue, name, project_data|
        build_row(issue, name, project_data, days_back, completed_status, completed_resolution, filter)
      end
      rows.sort_by! { |r| -r[:completed_date].to_time.to_i }

      McpServer.render_rows(rows, empty: 'No completed work found.') { |r| format_line(r) }
    end

    def self.build_row issue, project_name, project_data, days_back, completed_status, completed_resolution, filter
      started, stopped = issue.started_stopped_times
      return nil unless stopped

      completed_date = stopped.to_date
      return nil if past_cutoff?(completed_date, project_data[:today], days_back)

      status_at_done, resolution_at_done = issue.status_resolution_at_done
      return nil unless matches_completion?(status_at_done, resolution_at_done,
                                            completed_status, completed_resolution)
      return nil unless McpServer.matches_history?(issue, project_data[:end_time], filter)

      {
        key: issue.key,
        summary: issue.summary,
        type: issue.type,
        completed_date: completed_date,
        cycle_time_days: started ? (completed_date - started.to_date).to_i + 1 : nil,
        flow_efficiency: McpServer.flow_efficiency_percent(issue, stopped),
        status_at_done: status_at_done&.name,
        resolution_at_done: resolution_at_done,
        project: project_name
      }
    end

    def self.past_cutoff? completed_date, today, days_back
      return false unless days_back

      completed_date < today - days_back
    end

    def self.matches_completion? status_at_done, resolution_at_done, completed_status, completed_resolution
      return false if completed_status && status_at_done&.name != completed_status
      return false if completed_resolution && completed_resolution != resolution_at_done

      true
    end

    def self.format_line row
      ct = row[:cycle_time_days] ? "#{row[:cycle_time_days]}d" : 'unknown'
      fe = row[:flow_efficiency] ? " | FE: #{row[:flow_efficiency]}%" : ''
      completion = [row[:status_at_done], row[:resolution_at_done]].compact.join(' / ')
      "#{row[:key]} | #{row[:project]} | #{row[:type]} | #{row[:completed_date]} | " \
        "Cycle time: #{ct}#{fe} | #{completion} | #{row[:summary]}"
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
                  **history_args)
      project ||= project_name
      filter = McpServer::HistoryFilter.from(**history_args)

      rows = McpServer.collect_rows(server_context, project) do |issue, name, project_data|
        build_row(issue, name, project_data, current_status, current_column, filter)
      end
      rows.sort_by! { |r| r[:created] }

      McpServer.render_rows(rows, empty: 'No unstarted work found.') { |r| format_line(r) }
    end

    def self.build_row issue, project_name, project_data, current_status, current_column, filter
      started, stopped = issue.started_stopped_times
      return nil if started || stopped
      return nil unless McpServer.matches_current_state?(issue, current_status, current_column)
      return nil unless McpServer.matches_history?(issue, project_data[:end_time], filter)

      {
        key: issue.key,
        summary: issue.summary,
        status: issue.status.name,
        type: issue.type,
        created: issue.created.to_date,
        project: project_name
      }
    end

    def self.format_line row
      "#{row[:key]} | #{row[:project]} | #{row[:type]} | #{row[:status]} | " \
        "Created: #{row[:created]} | #{row[:summary]}"
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

      totals = accumulate_times(server_context, project, issue_state, group_by)
      rows = totals.map { |name, data| summary_row(name, data) }.sort_by { |r| -r[:avg_days] }

      McpServer.render_rows(rows, empty: 'No data found.') { |r| format_line(r, group_by) }
    end

    def self.accumulate_times server_context, project, issue_state, group_by
      totals = Hash.new { |hash, key| hash[key] = { total_seconds: 0.0, visit_count: 0 } }
      McpServer.each_allowed_issue(server_context, project) do |issue, _name, project_data|
        next unless select_issues(issue, issue_state)

        time_map_for(issue, project_data[:end_time], group_by).each do |name, seconds|
          totals[name][:total_seconds] += seconds
          totals[name][:visit_count] += 1
        end
      end
      totals
    end

    def self.time_map_for issue, end_time, group_by
      if group_by == 'column'
        McpServer.time_per_column(issue, end_time)
      else
        McpServer.time_per_status(issue, end_time)
      end
    end

    def self.summary_row name, data
      {
        name: name,
        total_days: (data[:total_seconds] / 86_400.0).round(1),
        avg_days: (data[:total_seconds] / data[:visit_count] / 86_400.0).round(1),
        visit_count: data[:visit_count]
      }
    end

    def self.format_line row, group_by
      label = group_by == 'column' ? 'Column' : 'Status'
      "#{label}: #{row[:name]} | Avg: #{row[:avg_days]}d | Total: #{row[:total_days]}d | Issues: #{row[:visit_count]}"
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
