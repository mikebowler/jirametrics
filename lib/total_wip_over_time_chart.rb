require 'pathname'

class TotalWipOverTimeChart
  attr_accessor :issues, :cycletime, :date_range

  # Extract this to superclass when it's all working.
  def render caller_binding
    basename = Pathname.new(File.realpath(__FILE__)).basename.to_s
    raise "Unexpected filename #{basename.inspect}" unless basename =~ /^(.+)\.rb$/

    erb = ERB.new File.read "html/#{$1}.erb"
    erb.result(caller_binding)
  end

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

  def run
    list = make_start_stop_sequence_for_issues
    active_issues = []

    chart_data = []

    # days_issues = []
    days_issues_completed = []
    current_date = list.first.first.to_date
    list.each do |time, action, issue|
      new_date = time.to_date
      unless new_date == current_date
        all_issues_active_today = (active_issues.dup + days_issues_completed).uniq(&:key).sort {|a,b| a.key<=>b.key}
        chart_data << [current_date, all_issues_active_today, days_issues_completed]
        days_issues_completed = []
        current_date = new_date
      end

      if action == 'start'
        active_issues << issue
      elsif action == 'stop'
        active_issues.delete(issue)
        days_issues_completed << issue
      else
        raise "Unexpected action #{action}"
      end
    end

    date_range = @date_range
    date_range = (date_range.begin.to_date..date_range.end.to_date)

    data_sets = []
    data_sets << {
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
        'data' => dataset_by_age(
          chart_data: chart_data, age_range: age_range, date_range: date_range, label: label
        ),
        'backgroundColor' => color
      }
    end

    render(binding)
  end

  def chart_data_starting_entry chart_data:, date:
    data = chart_data.find { |a| a.first == date }
    return data unless data.nil?

    last_data = nil
    chart_data.each do |data|
      return last_data if last_data && last_data[0] >= date

      last_data = data
    end

    if last_data.nil?
      [date, [], []]
    else
      last_data
    end
  end

  def dataset_by_age chart_data:, age_range:, date_range:, label:
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
          "#{i.key} : #{i.summary} (#{age} day#{'s' unless age == 1})"
        end
      }
    end
  end
end