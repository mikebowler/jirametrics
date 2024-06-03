# frozen_string_literal: true

require 'erb'
require 'jirametrics/self_or_issue_dispatcher'

class HtmlReportConfig
  include SelfOrIssueDispatcher
  include DiscardChangesBefore

  attr_reader :file_config, :sections

  def self.define_chart name:, classname:, deprecated_warning: nil, deprecated_date: nil
    lines = []
    lines << "def #{name} &block"
    lines << '  block = ->(_) {} unless block'
    if deprecated_warning
      lines << "  deprecated date: #{deprecated_date.inspect}, message: #{deprecated_warning.inspect}"
    end
    lines << "  execute_chart #{classname}.new(block)"
    lines << 'end'
    module_eval lines.join("\n"), __FILE__, __LINE__
  end

  define_chart name: 'aging_work_bar_chart', classname: 'AgingWorkBarChart'
  define_chart name: 'aging_work_table', classname: 'AgingWorkTable'
  define_chart name: 'cycletime_scatterplot', classname: 'CycletimeScatterplot'
  define_chart name: 'daily_wip_chart', classname: 'DailyWipChart'
  define_chart name: 'daily_wip_by_age_chart', classname: 'DailyWipByAgeChart'
  define_chart name: 'daily_wip_by_blocked_stalled_chart', classname: 'DailyWipByBlockedStalledChart'
  define_chart name: 'daily_wip_by_parent_chart', classname: 'DailyWipByParentChart'
  define_chart name: 'throughput_chart', classname: 'ThroughputChart'
  define_chart name: 'expedited_chart', classname: 'ExpeditedChart'
  define_chart name: 'cycletime_histogram', classname: 'CycletimeHistogram'
  define_chart name: 'estimate_accuracy_chart', classname: 'EstimateAccuracyChart'
  define_chart name: 'hierarchy_table', classname: 'HierarchyTable'

  define_chart name: 'daily_wip_by_type', classname: 'DailyWipChart',
    deprecated_warning: 'This is the same as daily_wip_chart. Please use that one', deprecated_date: '2024-05-23'
  define_chart name: 'story_point_accuracy_chart', classname: 'EstimateAccuracyChart',
    deprecated_warning: 'Renamed to estimate_accuracy_chart. Please use that one', deprecated_date: '2024-05-23'

  def initialize file_config:, block:
    @file_config = file_config
    @block = block
    @sections = []
  end

  def cycletime label = nil, &block
    @file_config.project_config.all_boards.each_value do |board|
      raise 'Multiple cycletimes not supported' if board.cycletime

      board.cycletime = CycleTimeConfig.new(parent_config: self, label: label, block: block)
    end
  end

  # Mostly this is its own method so it can be called from the config
  def included_projects
    @file_config.project_config.aggregate_config.included_projects
  end

  def run
    instance_eval(&@block)

    # The quality report has to be generated last because otherwise cycletime won't have been
    # set. Then we have to rotate it to the first position so it's at the top of the report.
    execute_chart DataQualityReport.new(@original_issue_times || {})
    @sections.rotate!(-1)

    html_directory = "#{Pathname.new(File.realpath(__FILE__)).dirname}/html"
    css = load_css html_directory: html_directory
    erb = ERB.new file_system.load(File.join(html_directory, 'index.erb'))
    file_system.save_file content: erb.result(binding), filename: @file_config.output_filename
  end

  def file_system
    @file_config.project_config.exporter.file_system
  end

  def log message
    file_system.log message
  end

  def load_css html_directory:
    base_css_filename = File.join(html_directory, 'index.css')
    base_css = file_system.load(base_css_filename)
    log("Loaded CSS:  #{base_css_filename}")

    extra_css_filename = settings['include_css']
    if extra_css_filename
      if File.exist?(extra_css_filename)
        base_css << "\n\n" << file_system.load(extra_css_filename)
        log("Loaded CSS:  #{extra_css_filename}")
      else
        log("Unable to find specified CSS file: #{extra_css_filename}")
      end
    end

    base_css
  end

  def board_id id = nil
    @board_id = id unless id.nil?
    @board_id
  end

  def timezone_offset
    @file_config.project_config.exporter.timezone_offset
  end

  def aging_work_in_progress_chart board_id: nil, &block
    block ||= ->(_) {}

    if board_id.nil?
      ids = issues.collect { |i| i.board.id }.uniq.sort
    else
      ids = [board_id]
    end

    ids.each do |id|
      execute_chart(AgingWorkInProgressChart.new(block)) do |chart|
        chart.board_id = id
      end
    end
  end

  def random_color
    "##{Random.bytes(3).unpack1('H*')}"
  end

  def html string, type: :body
    allowed_types = %i[body header]
    raise "Unexpected type: #{type} allowed_types: #{allowed_types.inspect}" unless allowed_types.include? type

    @sections << [string, type]
  end

  def sprint_burndown options = :points_and_counts
    execute_chart SprintBurndown.new do |chart|
      chart.options = options
    end
  end

  def discard_changes_before_hook issues_cutoff_times
    # raise 'Cycletime must be defined before using discard_changes_before' unless @cycletime

    @original_issue_times = {}
    issues_cutoff_times.each do |issue, cutoff_time|
      started = issue.board.cycletime.started_time(issue)
      if started && started <= cutoff_time
        # We only need to log this if data was discarded
        @original_issue_times[issue] = { cutoff_time: cutoff_time, started_time: started }
      end
    end
  end

  def dependency_chart &block
    execute_chart DependencyChart.new block
  end

  # have an explicit method here so that index.erb can call 'settings' just as any other erb can.
  def settings
    @file_config.project_config.settings
  end

  def execute_chart chart, &after_init_block
    project_config = @file_config.project_config

    chart.file_system = file_system
    chart.issues = issues
    chart.time_range = project_config.time_range
    chart.timezone_offset = timezone_offset
    chart.settings = settings

    chart.all_boards = project_config.all_boards
    chart.board_id = find_board_id if chart.respond_to? :board_id=
    chart.holiday_dates = project_config.exporter.holiday_dates

    time_range = @file_config.project_config.time_range
    chart.date_range = time_range.begin.to_date..time_range.end.to_date
    chart.aggregated_project = project_config.aggregated_project?

    after_init_block&.call chart

    html chart.run
  end

  def find_board_id
    @board_id || @file_config.project_config.guess_board_id
  end

  def issues
    @file_config.issues
  end

  # For use by the user config
  def find_board id
    @file_config.project_config.all_boards[id]
  end
end
