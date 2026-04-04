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
      tools: [AgingWorkTool],
      server_context: { projects: @projects, timezone_offset: @timezone_offset }
    )

    transport = MCP::Server::Transports::StdioTransport.new(server)
    transport.open
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
        }
      }
    )

    def self.call(server_context:, min_age_days: nil, project: nil)
      rows = []

      server_context[:projects].each do |project_name, project_data|
        next if project && project_name != project

        today = project_data[:today]
        project_data[:issues].each do |issue|
          started, stopped = issue.started_stopped_times
          next unless started && !stopped

          age = (today - started.to_date).to_i + 1
          next if min_age_days && age < min_age_days

          rows << {
            key: issue.key,
            summary: issue.summary,
            status: issue.status.name,
            type: issue.type,
            age_days: age,
            project: project_name
          }
        end
      end

      rows.sort_by! { |r| -r[:age_days] }

      if rows.empty?
        text = 'No aging work found.'
      else
        lines = rows.map do |r|
          "#{r[:key]} | #{r[:project]} | #{r[:type]} | #{r[:status]} | Age: #{r[:age_days]}d | #{r[:summary]}"
        end
        text = lines.join("\n")
      end

      MCP::Tool::Response.new([{ type: 'text', text: text }])
    end
  end
end
