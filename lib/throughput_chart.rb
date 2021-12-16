# frozen_string_literal: true

class ThroughputChart < ChartBase
  attr_accessor :issues, :cycletime, :date_range

  def run
    time_periods = calculate_time_periods
    data_sets = []
    data_sets << daily_throughput_dataset(color: 'gray')
    data_sets << weekly_throughput_dataset(periods: time_periods, color: 'black')

    render(binding, __FILE__)
  end

  def calculate_time_periods
    first_day = @date_range.begin
    first_day = case first_day.wday
      when 0 then first_day + 1
      when 1 then first_day
      else first_day + (8 - first_day.wday)
    end

    periods = []

    loop do
      last_day = first_day + 6
      return periods unless @date_range.include? last_day

      periods << (first_day..last_day)
      first_day = last_day + 1
    end
  end

  def closed_issues
    closed_issues = @issues.collect do |issue|
      stop_date = cycletime.stopped_time(issue)&.to_date
      [stop_date, issue] unless stop_date.nil?
    end.compact
    closed_issues.sort_by(&:first)
  end

  def daily_throughput_dataset color:
    hash = closed_issues.group_by(&:first)
    data = @date_range.collect do |date|
      next unless hash.has_key? date
      { 'y' => hash[date].size,
        'x' => hash[date].first.first,
        'title' => hash[date].collect {|stop_date, issue| "#{issue.key} : #{issue.summary}"} #'asdf' #["#{issue.key} : #{cycle_time} day#{'s' unless cycle_time == 1}",issue.summary]
      }
    end.compact
      {
        'label' => 'Daily throughput',
        'data' => data,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => color
      }
  end

  def weekly_throughput_dataset periods:, color:
    data = periods.collect do |period|
      closed_issues = @issues.collect do |issue|
        stop_date = cycletime.stopped_time(issue)&.to_date
        [stop_date, issue] if stop_date && period.include?(stop_date)
      end.compact

      { 'y' => closed_issues.size,
        'x' => period.end,
        'title' => closed_issues.collect {|stop_date, issue| "#{issue.key} : #{issue.summary}"}
      }
    end

    {
      'label' => 'Weekly throughput',
      'data' => data,
      'fill' => false,
      'showLine' => true,
      'backgroundColor' => color
    }
  end
end
