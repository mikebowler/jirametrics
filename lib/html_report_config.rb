# frozen_string_literal: true

require 'erb'
require './lib/self_or_issue_dispatcher'

class HtmlReportConfig
  include SelfOrIssueDispatcher
  include DiscardChangesBefore

  attr_reader :file_config, :sections

  def initialize file_config:, block:
    @file_config = file_config
    @block = block
    # @cycletimes = []
    @sections = []
    @expedited_priority_name = 'Highest'
  end

  def cycletime label = nil, &block
    # TODO: This is about to become deprecated

    @file_config.project_config.all_boards.each do |_id, board|
      raise 'Multiple cycletimes not supported yet' if board.cycletime

      board.cycletime = CycleTimeConfig.new(parent_config: self, label: label, block: block)
    end
  end

  def run
    instance_eval(&@block)

    # The quality report has to be generated last because otherwise cycletime won't have been
    # set. Then we have to rotate it to the first position so it's at the top of the report.
    execute_chart DataQualityReport.new(@original_issue_times || {})
    @sections.rotate!(-1)

    File.open @file_config.output_filename, 'w' do |file|
      erb = ERB.new File.read('html/index.erb')
      file.puts erb.result(binding)
    end
  end

  def board_id id = nil
    @board_id = id unless id.nil?
    @board_id
  end

  def timezone_offset
    @file_config.project_config.exporter.timezone_offset
  end

  def aging_work_in_progress_chart board_id: @board_id, &block
    execute_chart(AgingWorkInProgressChart.new(block)) do |chart|
      chart.board_id = board_id
    end
  end

  def aging_work_bar_chart
    execute_chart AgingWorkBarChart.new
  end

  def aging_work_table priority_name = @expedited_priority_name
    execute_chart AgingWorkTable.new(priority_name)
  end

  def cycletime_scatterplot &block
    execute_chart CycletimeScatterplot.new block
  end

  def total_wip_over_time_chart &block
    puts 'Deprecated(total_wip_over_time_chart). Use daily_wip_by_age_chart instead.'
    execute_chart DailyWipByAgeChart.new block
  end

  def daily_wip_chart &block
    execute_chart DailyWipChart.new(block)
  end

  def daily_wip_by_age_chart &block
    execute_chart DailyWipByAgeChart.new block
  end

  def daily_wip_by_type &block
    execute_chart DailyWipChart.new block
  end

  def daily_wip_by_blocked_stalled_chart
    execute_chart DailyWipByBlockedStalledChart.new
  end

  def throughput_chart &block
    execute_chart ThroughputChart.new(block)
  end

  def blocked_stalled_chart
    puts 'Deprecated(blocked_stalled_chart). Use daily_wip_by_blocked_stalled_chart instead.'
    execute_chart DailyWipByBlockedStalledChart.new
  end

  def expedited_chart priority_name = @expedited_priority_name
    execute_chart ExpeditedChart.new(priority_name)
  end

  def cycletime_histogram &block
    execute_chart CycletimeHistogram.new block
  end

  def random_color
    "\##{Random.bytes(3).unpack1('H*')}"
  end

  def html string, type: :body
    raise "Unexpected type: #{type}" unless [:body, :header].include? type

    @sections << [string, type]
  end

  def sprint_burndown options = :points_and_counts
    execute_chart SprintBurndown.new do |chart|
      chart.options = options
    end
  end

  def story_point_accuracy_chart &block
    execute_chart StoryPointAccuracyChart.new block
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

  def discarded_changes_report
    puts 'Deprecated(discarded_changes_report) No need to specify this anymore as this information is ' \
     'now included in the data quality checks.'
  end

  def dependency_chart &block
    execute_chart DependencyChart.new block
  end

  def execute_chart chart, &after_init_block
    project_config = @file_config.project_config

    chart.issues = issues
    chart.time_range = project_config.time_range
    chart.possible_statuses = project_config.possible_statuses
    chart.timezone_offset = timezone_offset
    chart.sprints_by_board = project_config.sprints_by_board

    chart.all_boards = project_config.all_boards
    chart.board_id = find_board_id if chart.respond_to? :board_id=
    chart.holiday_dates = project_config.exporter.holiday_dates

    time_range = @file_config.project_config.time_range
    chart.date_range = time_range.begin.to_date..time_range.end.to_date
    chart.aggregate_project = project_config.aggregate_project?

    after_init_block&.call chart

    html chart.run
  end

  def find_board_id
    @board_id || @file_config.project_config.guess_board_id
  end

  def issues
    @file_config.issues
  end
end
