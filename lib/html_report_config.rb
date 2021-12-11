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
      title: 'foo',
      barPercentage: 1.0,
      categoryPercentage: 1.0,
      data: days_at_percentage_threshold_for_all_columns(
        percentage: 85, issues: @file_config.issues, columns: board_metadata
      ).drop(1)
    }

    column_headings = board_metadata.collect(&:name)
    @sections << render(binding)
  end

  def cycletime_scatterplot
    completed_issues = @file_config.issues.select { |issue| @cycletime.done? issue }
    data_sets = []
    completed_issues.collect(&:type).uniq.each_with_index do |type, index|
      data_sets << {
        'label' => type,
        'data' => completed_issues
          .select { |issue| issue.type == type }
          .collect do |issue|
            cycle_time = @cycletime.cycletime(issue)
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

  # private

  def days_at_percentage_threshold_for_all_columns percentage:, issues:, columns:
    accumulated_status_ids = []
    columns.reverse.collect do |column|
      accumulated_status_ids += column.status_ids
      day_count = date_that_percentage_of_issues_leave_statuses(
        percentage: percentage, issues: issues, status_ids: accumulated_status_ids
      )

    end.reverse
  end

  def date_that_percentage_of_issues_leave_statuses percentage:, issues:, status_ids:
    days_to_transition = issues.collect do |issue|
      transition_time = issue.first_time_in_status(*status_ids)
      if transition_time.nil?
        # This item has never left this particular column. Exclude it from the
        # calculation
        nil
      else
        start_time = @cycletime.started_time(issue)
        if start_time.nil?
          # This item went straight from created to done so we can't determine the
          # start time. Exclude this record from the calculation
          nil
        else
          (transition_time - start_time).to_i + 1
        end
      end
    end.compact
    index = days_to_transition.size * percentage / 100
    # puts '-',"status_ids=#{status_ids.inspect}"
    # puts "index=#{index} days_to_transition=#{days_to_transition.sort.inspect}"
    days_to_transition.sort[index.to_i]
  end

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
