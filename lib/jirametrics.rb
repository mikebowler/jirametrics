# frozen_string_literal: true

require 'require_all'

class JiraMetrics
  def self.run
    config_file = './config.rb'
    if ENV['config_file']
      config_file = ENV['config_file']
      if File.exist? config_file
        puts "Using config file #{config_file}"
      else
        puts "Cannot find config file #{config_file}"
      end
    end
    puts "config=#{config_file}"
    # require_all 'jirametrics/'
    require 'jirametrics/chart_base'
    require 'jirametrics/rules'
    require 'jirametrics/grouping_rules'
    require 'jirametrics/daily_wip_chart'
    require 'jirametrics/groupable_issue_chart'
    require 'jirametrics/discard_changes_before'

    require 'jirametrics/aggregate_config'
    require 'jirametrics/expedited_chart'
    require 'jirametrics/board_config'
    require 'jirametrics/file_config'
    require 'jirametrics/trend_line_calculator'
    require 'jirametrics/status'
    require 'jirametrics/issue_link'
    require 'jirametrics/story_point_accuracy_chart'
    require 'jirametrics/status_collection'
    require 'jirametrics/sprint'
    require 'jirametrics/issue'
    require 'jirametrics/daily_wip_by_age_chart'
    require 'jirametrics/aging_work_in_progress_chart'
    require 'jirametrics/cycletime_scatterplot'
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
    require 'jirametrics/json_file_loader'
    require 'jirametrics/blocked_stalled_change'
    require 'jirametrics/board_column'
    require 'jirametrics/anonymizer'
    require 'jirametrics/downloader'
    require 'jirametrics/fix_version'
    require 'jirametrics/download_config'
    require 'jirametrics/columns_config'
    require 'jirametrics/hierarchy_table'
    require 'jirametrics/board'
    require config_file

    puts ARGV.inspect
    if ARGV[0] == 'download'
      Exporter.instance.download
    elsif ARGV[0] == 'export'
      Exporter.instance.export
    end
  end

  # Dir.foreach('lib/jirametrics') {|file| puts "require 'jirametrics/#{$1}'" if file =~ /^(.+)\.rb$/}
end
