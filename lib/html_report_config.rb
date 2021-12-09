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
    aging_issues = @file_config.issues.select { |issue| @cycletime.in_progress? issue }

    board_metadata = @file_config.project_config.board_metadata

    data_sets = []
    aging_issues.collect(&:type).uniq.each_with_index do |type, index|
      data_sets << {
        'type' => 'line',
        'label' => type,
        'data' => aging_issues
          .select { |issue| issue.type == type }
          .collect do |issue|
            age = @cycletime.age(issue)
            { 'y' => @cycletime.age(issue),
              # 'x' => (column_index_for issue: issue, board_metadata: board_metadata) * 10,
              'x' => (column_for issue: issue, board_metadata: board_metadata).name,
              'title' => ["#{issue.key} : #{age} day#{'s' unless age == 1}", issue.summary]
            }
          end,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => %w[blue green orange yellow gray black][index]
      }
    end
    data_sets << {
      type: 'bar',
      label: '85%',
      barPercentage: 1.0,
      categoryPercentage: 1.0,
      data: [10, 20, 30, 40, 50, 80, 100]
    }

    column_headings = board_metadata.collect(&:name)
    @sections << render(binding)
  end

  def cycletime_scatterplot
    cutoff = DateTime.parse('2021-06-01')

    completed_issues = @file_config.issues.select { |issue| @cycletime.done? issue }
    data_sets = []
    completed_issues.collect(&:type).uniq.each_with_index do |type, index|
      data_sets << {
        'label' => type,
        'data' => completed_issues
          .select { |issue| issue.type == type }
          .collect do |issue|
            cycle_time = @cycletime.cycletime(issue)
            puts issue.key if @cycletime.stopped_time(issue) < cutoff
            { 'y' => cycle_time,
              'x' => @cycletime.stopped_time(issue),
              'title' => ["#{issue.key} : #{cycle_time} day#{'s' unless cycle_time == 1}",issue.summary]
            }
          end,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => %w[blue green orange yellow gray black][index]
      }
    end

    @sections << render(binding)
  end

  private

  def render caller_binding
    caller_method_name = caller_locations(1, 1)[0].label

    erb = ERB.new File.read "html/#{caller_method_name}.erb"
    erb.result(caller_binding)
  end

  def column_for issue:, board_metadata:
    board_metadata.find do |board_column|
      board_column.status_ids.include? issue.status_id
    end
  end
end
