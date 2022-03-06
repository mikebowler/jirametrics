# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkBarChart < ChartBase
  @@next_id = 0
  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses, :date_range

  def run
    aging_issues = @issues.select { |issue| @cycletime.started_time(issue) && @cycletime.stopped_time(issue).nil? }
    data_quality = scan_data_quality(aging_issues)

    # Consider sorting statuses by board_id - left to right across the board
    status_names = []
    aging_issues.each do |issue|
      issue.changes.each do |change|
        next unless change.status?

        status_names << change.value
      end
    end

    aging_issues.sort! { |a, b| @cycletime.age(b) <=> @cycletime.age(a) }
    data_sets = []
    aging_issues.each do |issue|
      new_dataset = data_sets_for issue: issue
      new_dataset.each do |data|
        data_sets << data
      end
    end

    render(binding, __FILE__)
  end

  def data_sets_for issue:
    # label = issue.key
    color = %w[blue green red gray black yellow]
    y = "#{issue.key} (#{label_days @cycletime.age(issue)})"

    issue_started_time = @cycletime.started_time(issue)

    previous_start = nil
    previous_status = nil

    data = []
    issue.changes.each do |change|
      next unless change.status?

      unless previous_start.nil? || previous_start < issue_started_time

        hash = {
          type: 'bar',
          label: "#{issue.key}-#{@@next_id += 1}",
          data: [{
            x: [previous_start, change.time],
            y: y,
            title: previous_status
          }],
          backgroundColor: color.sample,
          borderRadius: 0,
          stacked: true
        }
        data << hash if date_range.include?(change.time.to_date)
      end

      previous_start = change.time
      previous_status = change.value
    end

    if previous_start
      data << {
        type: 'bar',
        label: "#{issue.key}-#{@@next_id += 1}",
        data: [{
          x: [previous_start, date_range.end + 1],
          y: y,
          title: previous_status
        }],
        backgroundColor: color.sample,
        borderRadius: 0,
        stacked: true
      }
    end

    data
  end
end
