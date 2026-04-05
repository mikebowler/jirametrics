# frozen_string_literal: true

require 'thor'
require 'require_all'

# This one does need to be loaded early. The rest will be loaded later.
require 'jirametrics/file_system'

class JiraMetrics < Thor
  def self.exit_on_failure?
    true
  end

  map %w[--version -v] => :__print_version

  desc '--version, -v', 'print the version'
  def __print_version
    puts Gem.loaded_specs['jirametrics'].version
  end

  option :config
  option :name
  desc 'export', "Export data into either reports or CSV's as per the configuration"
  def export
    load_config options[:config]
    Exporter.instance.export(name_filter: options[:name] || '*')
  end

  option :config
  option :name
  desc 'download', 'Download data from Jira'
  def download
    load_config options[:config]
    Exporter.instance.download(name_filter: options[:name] || '*')
  end

  option :config
  option :name
  desc 'go', 'Same as running download, followed by export'
  def go
    load_config options[:config]
    Exporter.instance.download(name_filter: options[:name] || '*')

    load_config options[:config]
    Exporter.instance.export(name_filter: options[:name] || '*')
  end

  option :config
  desc 'info', 'Dump information about one issue'
  def info key
    load_config options[:config]
    Exporter.instance.info(key, name_filter: options[:name] || '*')
  end

  option :config
  option :name
  desc 'mcp', 'Start in MCP (Model Context Protocol) server mode'
  def mcp
    load_config options[:config]
    require 'jirametrics/mcp_server'

    Exporter.instance.file_system.log_only = true

    projects = {}
    aggregates = {}
    Exporter.instance.each_project_config(name_filter: options[:name] || '*') do |project|
      project.evaluate_next_level
      project.run load_only: true
      projects[project.name || 'default'] = {
        issues: project.issues,
        today: project.time_range.end.to_date,
        end_time: project.time_range.end
      }
    rescue StandardError => e
      if e.message.start_with? 'This is an aggregated project'
        names = project.aggregate_project_names
        aggregates[project.name] = names if names.any?
        next
      end
      next if e.message.start_with? 'No data found'

      raise
    end

    McpServer.new(projects: projects, aggregates: aggregates, timezone_offset: Exporter.instance.timezone_offset).run
  end

  option :config
  desc 'stitch', 'Dump information about one issue'
  def stitch stitch_file = 'stitcher.erb'
    load_config options[:config]
    Exporter.instance.stitch stitch_file
  end

  no_commands do
    def load_config config_file, file_system: FileSystem.new
      config_file = './config.rb' if config_file.nil?

      if file_system.file_exist? config_file
        # The fact that File.exist can see the file does not mean that require will be
        # able to load it. Convert this to an absolute pathname now for require.
        config_file = File.absolute_path(config_file).to_s
      else
        file_system.error "Cannot find configuration file #{config_file.inspect}"
        exit 1
      end

      require_rel 'jirametrics'
      load config_file
    end
  end
end
