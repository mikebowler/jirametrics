# frozen_string_literal: true

require 'thor'

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
  def info keys
    load_config options[:config]
    Exporter.instance.info(keys, name_filter: options[:name] || '*')
  end

  private

  def load_config config_file
    config_file = './config.rb' if config_file.nil?

    if File.exist? config_file
      # The fact that File.exist can see the file does not mean that require will be
      # able to load it. Convert this to an absolute pathname now for require.
      config_file = File.absolute_path(config_file).to_s
    else
      puts "Cannot find configuration file #{config_file.inspect}"
      exit 1
    end

    require 'jirametrics/value_equality'
    require 'jirametrics/chart_base'
    require 'jirametrics/rules'
    require 'jirametrics/grouping_rules'
    require 'jirametrics/daily_wip_chart'
    require 'jirametrics/groupable_issue_chart'
    require 'jirametrics/css_variable'

    require 'jirametrics/aggregate_config'
    require 'jirametrics/expedited_chart'
    require 'jirametrics/board_config'
    require 'jirametrics/file_config'
    require 'jirametrics/jira_gateway'
    require 'jirametrics/trend_line_calculator'
    require 'jirametrics/status'
    require 'jirametrics/issue_link'
    require 'jirametrics/estimate_accuracy_chart'
    require 'jirametrics/status_collection'
    require 'jirametrics/sprint'
    require 'jirametrics/issue'
    require 'jirametrics/daily_wip_by_age_chart'
    require 'jirametrics/daily_wip_by_parent_chart'
    require 'jirametrics/aging_work_in_progress_chart'
    require 'jirametrics/cycletime_scatterplot'
    require 'jirametrics/flow_efficiency_scatterplot'
    require 'jirametrics/sprint_issue_change_data'
    require 'jirametrics/cycletime_histogram'
    require 'jirametrics/daily_wip_by_blocked_stalled_chart'
    require 'jirametrics/html_report_config'
    require 'jirametrics/data_quality_report'
    require 'jirametrics/aging_work_bar_chart'
    require 'jirametrics/change_item'
    require 'jirametrics/project_config'
    require 'jirametrics/dependency_chart'
    require 'jirametrics/cycletime_config'
    require 'jirametrics/tree_organizer'
    require 'jirametrics/aging_work_table'
    require 'jirametrics/sprint_burndown'
    require 'jirametrics/self_or_issue_dispatcher'
    require 'jirametrics/throughput_chart'
    require 'jirametrics/exporter'
    require 'jirametrics/file_system'
    require 'jirametrics/blocked_stalled_change'
    require 'jirametrics/board_column'
    require 'jirametrics/anonymizer'
    require 'jirametrics/downloader'
    require 'jirametrics/fix_version'
    require 'jirametrics/download_config'
    require 'jirametrics/columns_config'
    require 'jirametrics/hierarchy_table'
    require 'jirametrics/estimation_configuration'
    require 'jirametrics/board'
    require 'jirametrics/daily_view'
    load config_file
  end
end
