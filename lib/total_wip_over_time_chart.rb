# frozen_string_literal: true

require 'pathname'

class TotalWipOverTimeChart < ChartBase
  attr_accessor :issues, :cycletime, :date_range

  # Returns a list of tuples [time, action(start or stop), issue] in sorted order
  def make_start_stop_sequence_for_issues
    list = []
    @issues.each do |issue|
      started = @cycletime.started_time(issue)
      stopped = @cycletime.stopped_time(issue)
      next unless started

      list << [started, 'start', issue]
      list << [@cycletime.stopped_time(issue), 'stop', issue] unless stopped.nil?
    end
    list.sort { |a, b| a.first <=> b.first }
  end

  def make_chart_data issue_start_stops:
    # chart_data is a list of [date, issues, issues_completed] groupings
    return [] if issue_start_stops.empty?

    active_issues = []
    chart_data = []
    days_issues_completed = []

    current_date = issue_start_stops.first.first.to_date
    issue_start_stops.each do |time, action, issue|
      new_date = time.to_date
      unless new_date == current_date
        all_issues_active_today = (active_issues.dup + days_issues_completed).uniq(&:key).sort_by(&:key)
        chart_data << [current_date, all_issues_active_today, days_issues_completed]
        days_issues_completed = []
        current_date = new_date
      end

      case action
      when 'start'
        active_issues << issue
      when 'stop'
        active_issues.delete(issue)
        days_issues_completed << issue
      else
        raise "Unexpected action #{action}"
      end
    end

    all_issues_active_today = (active_issues.dup + days_issues_completed).uniq(&:key).sort_by(&:key)
    chart_data << [current_date, all_issues_active_today, days_issues_completed]

    chart_data
  end

  def run
    chart_data = make_chart_data issue_start_stops: make_start_stop_sequence_for_issues

    date_range = (@date_range.begin.to_date..@date_range.end.to_date)

    data_sets = []
    data_sets << completed_data_set(chart_data: chart_data)

    [
      [29..nil, '#990000', 'More than four weeks'],
      [15..28, '#ce6300', 'Four weeks or less'],
      [8..14, '#ffd700', 'Two weeks or less'],
      [2..7, '#80bfff', 'A week or less'],
      [nil..1, '#aaaaaa', 'New today']
    ].each do |age_range, color, label|
      data_sets << {
        'type' => 'bar',
        'label' => label,
        'data' => incomplete_dataset(
          chart_data: chart_data, age_range: age_range, date_range: date_range, label: label
        ),
        'backgroundColor' => color
      }
    end

    render(binding, __FILE__)
  end

  def completed_data_set chart_data:
    {
      'type' => 'bar',
      'label' => 'Completed that day',
      'data' => chart_data.collect do |time, _issues, issues_completed|
        next unless date_range.include? time.to_date

        {
          x: time,
          y: -issues_completed.size,
          title: ['Work items completed'] + issues_completed.collect { |i| "#{i.key} : #{i.summary}" }.sort
        }
      end.compact,
      'backgroundColor' => '#009900',
      'borderRadius' => '5'
    }
  end

  # Return the first chart_data entry that we'll display. This is tricky because there may not be
  # an entry on the day we want and we might have to fabricate one.
  def chart_data_starting_entry chart_data:, date:
    exact_match = chart_data.find { |entry_date, _issues, _issues_completed| entry_date == date }
    return exact_match unless exact_match.nil?

    # We don't have an entry on the day we care about so look backwards for the last time we did
    # have data.
    last_data = nil
    chart_data.each do |data|
      return [date, last_data[1], last_data[2]] if last_data && data.first > date

      last_data = data
    end

    # We have no way to get real data so assume that nothing was in progress.
    [date, [], []]
  end

  def incomplete_dataset chart_data:, age_range:, date_range:, label:
    # chart_data is a list of [time, issues, issues_completed] groupings

    issues = []
    issues_completed = []
    data = nil

    date_range.collect do |date|
      if data.nil?
        data = chart_data_starting_entry chart_data: chart_data, date: date_range.begin
      else
        data = chart_data.find { |a| a.first == date }
      end

      # Not all days have data. For days that don't, use the previous days
      # data minus the completed work
      data = nil, issues - issues_completed, [] if data.nil?
      _change_time, issues, issues_completed = *data

      included_issues = issues.collect do |issue|
        age = (date - @cycletime.started_time(issue).to_date).to_i + 1
        [issue, age] if age_range.include? age
      end.compact

      {
        x: date,
        y: included_issues.size,
        title: [label] + included_issues.collect do |i, age|
          "#{i.key} : #{i.summary} (#{age} #{label_days age})"
        end
      }
    end
  end
end