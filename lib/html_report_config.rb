# frozen_string_literal: true

require 'erb'
require './lib/self_or_issue_dispatcher'

class HtmlReportConfig
  include SelfOrIssueDispatcher

  attr_reader :file_config

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
    chart = AgingWorkInProgressChart.new
    chart.issues = @file_config.issues
    chart.board_metadata = @file_config.project_config.board_metadata
    chart.cycletime = @cycletime
    @sections << chart.run
  end

  def cycletime_scatterplot
    chart = CycletimeScatterplot.new
    chart.issues = @file_config.issues
    chart.cycletime = @cycletime
    @sections << chart.run
  end

  def total_wip_over_time_chart
    chart = TotalWipOverTimeChart.new
    chart.issues = @file_config.issues
    chart.cycletime = @cycletime
    chart.date_range = @file_config.project_config.date_range
    @sections << chart.run
  end

  def throughput_chart
    chart = ThroughputChart.new
    chart.issues = @file_config.issues
    chart.cycletimes = [@cycletime]
    chart.date_range = @file_config.project_config.date_range
    @sections << chart.run
  end
end
