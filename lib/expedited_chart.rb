# frozen_string_literal: true

require './lib/chart_base'

class ExpeditedChart < ChartBase
  attr_accessor :issues, :cycletime, :board_metadata, :possible_statuses, :date_range

  def expedited_label
    'Immediate Gating'
  end

  def run
    expedited_issues = @issues.select do |issue|
      issue.changes.any? { |change| change.priority? && change.value == expedited_label }
    end

    data_sets = []
    # data_sets << make_start_points_data_set(expedited_issues)
    # data_sets << make_complete_points_data_set(expedited_issues)
    expedited_issues.each do |issue|
      data_sets << make_expedite_lines_data_set(issue: issue)
    end

    render(binding, __FILE__)
  end

  def make_start_points_data_set expedited_issues
    data = []
    expedited_issues.each do |issue|
      started_time = @cycletime.started_time(issue)
      next unless started_time
      next if started_time.to_date < date_range.begin

      data << {
        'y' => (started_time.to_date - issue.created.to_date).to_i + 1,
        'x' => started_time.to_date.to_s,
        'title' => ["#{issue.key} Started : #{issue.summary}"]
      }
    end

    {
      'label' => 'Start points',
      'data' => data,
      'fill' => false,
      'showLine' => false,
      'backgroundColor' => 'orange'
    }
  end

  def make_complete_points_data_set expedited_issues
    data = []
    expedited_issues.each do |issue|
      stopped_time = @cycletime.stopped_time(issue)
      next unless stopped_time

      data << {
        'y' => (stopped_time.to_date - issue.created.to_date).to_i + 1,
        'x' => stopped_time.to_date.to_s,
        'title' => ["#{issue.key} Completed : #{issue.summary}"]
      }
    end

    {
      'label' => 'Completed points',
      'data' => data,
      'fill' => false,
      'showLine' => false,
      'backgroundColor' => 'green'
    }
  end

  def earliest_date a, b
    return a if b.nil?
    return b if a.nil?

    [a, b].min
  end

  def later_date a, b
    return a if b.nil?
    return b if a.nil?

    [a, b].max
  end

  def make_point issue:, time:, label:
    {
      y: (time.to_date - issue.created.to_date).to_i + 1,
      x: time.to_date.to_s,
      title: ["#{issue.key} #{label} : #{issue.summary}"]
    }
  end

  def make_expedite_lines_data_set issue:
    started_time = @cycletime.started_time(issue)
    stopped_time = @cycletime.stopped_time(issue)

    data = []
    colors = []
    point_styles = []

    started = nil
    issue.changes.each do |change|
      if change.time == started_time || change.time == stopped_time
        label = 'Started'
        label = 'Stopped' if change.time == stopped_time

        data << make_point(issue: issue, time: change.time, label: label)
        colors << 'orange'
        point_styles << 'rect'
      end
      next unless change.priority?

      if change.value == expedited_label
        started = change.time

        data << make_point(issue: issue, time: later_date(date_range.begin, change.time), label: label)
        colors << 'red'
        point_styles << 'dash'
      elsif started
        data << make_point(issue: issue, time: later_date(date_range.begin, change.time), label: label)
        colors << 'black'
        point_styles << 'circle'
        started = nil
      end
    end

    if started && (stopped_time.nil? || (stopped_time && started > stopped_time))
      data << make_point(issue: issue, time: date_range.end, label: 'Still ongoing')
      colors << 'green'
      point_styles << 'rect'
      started = nil
    end

    {
      'type' => 'line',
      'label' => issue.key,
      'data' => data,
      'fill' => false,
      'showLine' => true,
      'backgroundColor' => colors,
      'borderColor' => colors,
      'pointStyle' => point_styles
    }
  end
end
