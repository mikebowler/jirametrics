# frozen_string_literal: true

require 'erb'
require './lib/self_or_issue_dispatcher'

class HtmlReportConfig
  include SelfOrIssueDispatcher

  attr_reader :file_config, :sections

  def initialize file_config:, block:
    @file_config = file_config
    @block = block
    @cycletimes = []
    @sections = []
  end

  def cycletime label = nil, &block
    raise 'Multiple cycletimes not supported yet' if @cycletime

    @cycletime = CycleTimeConfig.new(parent_config: self, label: label, block: block)
  end

  def run
    instance_eval(&@block)

    File.open @file_config.output_filename, 'w' do |file|
      erb = ERB.new File.read('html/index.erb')
      file.puts erb.result(binding)
    end
  end

  def aging_work_in_progress_chart
    execute_chart AgingWorkInProgressChart.new
  end

  def cycletime_scatterplot
    execute_chart CycletimeScatterplot.new
  end

  def total_wip_over_time_chart
    execute_chart TotalWipOverTimeChart.new
  end

  def throughput_chart
    execute_chart ThroughputChart.new
  end

  def blocked_stalled_chart
    execute_chart BlockedStalledChart.new
  end

  def expedited_chart
    execute_chart ExpeditedChart.new
  end

  def execute_chart chart
    chart.issues = @file_config.issues if chart.respond_to? :'issues='
    chart.cycletime = @cycletime if chart.respond_to? :'cycletime='
    chart.time_range = @file_config.project_config.time_range if chart.respond_to? :'time_range='
    chart.board_metadata = @file_config.project_config.board_metadata if chart.respond_to? :'board_metadata='
    chart.possible_statuses = @file_config.project_config.possible_statuses if chart.respond_to? :'possible_statuses='

    if chart.respond_to? :'date_range='
      time_range = @file_config.project_config.time_range
      chart.date_range = time_range.begin.to_date..time_range.end.to_date
    end

    @sections << chart.run
  end
end
