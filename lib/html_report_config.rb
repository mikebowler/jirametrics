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
    aging_issues.collect(&:type).uniq.each_with_index do |type|
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
        'backgroundColor' => colour_for(type: type)
      }
    end
    data_sets << {
      type: 'bar',
      label: '85%',
      barPercentage: 1.0,
      categoryPercentage: 1.0,
      data: days_at_percentage_threshold_for_all_columns(
        percentage: 85, issues: @file_config.issues, columns: board_metadata
      ).drop(1)
    }

    column_headings = board_metadata.collect(&:name)
    @sections << render(binding)
  end

  def total_wip_over_time_chart
    list = []
    active_issues = []
    @file_config.issues.each do |issue|
      started = @cycletime.started_time(issue)
      stopped = @cycletime.stopped_time(issue)
      next unless started

      list << [started, 'start', issue]
      list << [@cycletime.stopped_time(issue), 'stop', issue] unless stopped.nil?
    end

    chart_data = []

    days_issues = []
    days_issues_completed = []
    list.sort! { |a, b| a.first <=> b.first }
    current_date = list.first.first.to_date
    list.each do |time, action, issue|
      new_date = time.to_date
      unless new_date == current_date
        chart_data << [current_date, days_issues.uniq, days_issues_completed]
        days_issues = []
        days_issues_completed = []
        current_date = new_date
      end

      days_issues << issue
      if action == 'start'
        active_issues << issue
      elsif action == 'stop'
        active_issues.delete(issue)
        days_issues_completed << issue
      else
        raise "Unexpected action #{action}"
      end
    end

    today = Date.today
    graphable_date_range = (today - 90..today)
    data_sets = []
    data_sets << {
      'type' => 'bar',
      'label' => 'Completed that day',
      'data' => chart_data.collect do |time, _issues, issues_completed|
        if time >= graphable_date_range.begin && time < graphable_date_range.end
          {
            x: time,
            y: -issues_completed.size,
            title: ['Work items completed'] + issues_completed.collect { |i| "#{i.key} : #{i.summary}" }
          }
        else
          nil
        end
      end.compact,
      backgroundColor: 'green'
    }
    data_sets << {
      'type' => 'bar',
      'label' => 'More than four weeks',
      'data' => foo_data_set(chart_data: chart_data, min_age: 29, max_age: nil, label: 'More than four weeks'),
      'backgroundColor' => 'red'
    }
    data_sets << {
      'type' => 'bar',
      'label' => 'Less than four weeks',
      'data' => foo_data_set(chart_data: chart_data, min_age: 14, max_age: 28, label: 'Less than four weeks'),
      'backgroundColor' => 'purple'
    }
    data_sets << {
      'type' => 'bar',
      'label' => 'Less than two weeks',
      'data' => foo_data_set(chart_data: chart_data, min_age: 0, max_age: 3, label: 'Less than two weeks'),
      'backgroundColor' => 'brown'
    }
    data_sets << {
      'type' => 'bar',
      'label' => 'Less than a week',
      'data' => foo_data_set(chart_data: chart_data, min_age: 3, max_age: 8, label: 'Less than a week'),
      'backgroundColor' => 'gray'
    }
    data_sets << {
      'type' => 'bar',
      'label' => 'Less than two days',
      'data' => foo_data_set(chart_data: chart_data, min_age: 0, max_age: 3, label: 'Less than two days'),
      'backgroundColor' => 'lightgray'
    }
    @sections << render(binding)
  end

  def foo_data_set chart_data:, min_age:, max_age:, label:
    # chart_data is a list of [time, issues, issues_completed] groupings

    today = Date.today
    graphable_date_range = (today - 90..today)
    chart_start_date = graphable_date_range.begin
    chart_end_date = graphable_date_range.end
    # chart_end_date = Date.today
    # chart_start_date = chart_end_date - 90 #chart_data.first.first.to_date
    data = [chart_start_date, [], []]
    chart_start_date.upto(chart_end_date).collect do |date|
      # Not all days have data. For days that don't, use the previous days data
      data = chart_data.find { |a| a.first == date } || data
      time, issues, _issues_completed = *data

      included_issues = issues.collect do |issue|
        age = (time - @cycletime.started_time(issue)).to_i + 1
        if age >= min_age && (max_age.nil? || age < max_age)
          [issue, age]
        else
          nil
        end
      end.compact

      {
        x: date,
        y: included_issues.size,
        title: [label] + included_issues.collect { |i,age| "#{i.key} : #{i.summary} (#{age} days)" }
      } 
    end
  end

  def cycletime_scatterplot
    completed_issues = @file_config.issues.select { |issue| @cycletime.done? issue }
    data_sets = []
    completed_issues.collect(&:type).uniq.each_with_index do |type|
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
        'backgroundColor' => colour_for(type: type)
      }
    end

    @sections << render(binding)
  end

  # private

  def days_at_percentage_threshold_for_all_columns percentage:, issues:, columns:
    accumulated_status_ids = []
    columns.reverse.collect do |column|
      accumulated_status_ids += column.status_ids
      date_that_percentage_of_issues_leave_statuses(
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

  def colour_for type:
    case type.downcase
    when 'story' then 'green'
    when 'task' then 'blue'
    when 'bug', 'defect' then 'orange'
    when 'spike' then 'gray'
    else 'black'
    end
  end
end
