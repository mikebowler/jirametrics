# frozen_string_literal: true

class StoryPointAccuracyChart < ChartBase
  def initialize configuration_block = nil
    super()

    @groupings = []
    header_text 'Story Point Accuracy'
    description_text <<-HTML
      <p>
        This chart graphs story point estimates against actual recorded cycle times. Since story point
        estimates can change over time, we're graphing the estimate at the time that the story started.
      </p>
      <p>
        The color coding indicates how many issues fell at that intersection of estimate and actual.
      </p>
    HTML

    if configuration_block
      instance_eval(&configuration_block)
    else
      grouping range: 1..1, color: '#dcdcde'
      grouping range: 2..3, color: '#c3c4c7'
      grouping range: 4..6, color: '#a7aaad'
      grouping range: 7..10, color: '#8c8f94'
      grouping range: 11..15, color: '#787682'
      grouping range: 16..20, color: '#646970'
      grouping range: 21..30, color: '#3c434a'
      grouping range: 31.., color: '#101517'
    end
  end

  def run
    data_sets = scan_issues

    # If no issues have story points then don't even show the chart.
    # return '' if data_sets.empty?

    wrap_and_render(binding, __FILE__)
  end

  def scan_issues
    hash = {}
    issues.each do |issue|
      cycletime = issue.board.cycletime
      start_time = cycletime.started_time(issue)
      stop_time = cycletime.stopped_time(issue)

      next unless start_time && stop_time

      estimate = story_points_at issue: issue, start_time: start_time
      cycle_time = (stop_time.to_date - start_time.to_date).to_i + 1

      next if estimate.nil? || estimate.empty?

      key = [estimate.to_f, cycle_time]
      (hash[key] ||= []) << issue
    end

    @groupings.collect do |range, color|
      data = hash.select { |_key, issues| range.include? issues.size }.collect do |key, values|
        estimate, cycle_time = *key
        title = ["Estimate: #{estimate}pts, Cycletime: #{label_days(cycle_time)}, #{values.size} issues"] +
          values.collect { |issue| "#{issue.key}: #{issue.summary}" }
        {
          'x' => cycle_time,
          'y' => estimate,
          'title' => title
        }
      end.compact
      next if data.empty?

      {
        'label' => range_to_s(range),
        'data' => data,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => color
      }
    end.compact
  end

  def grouping range:, color:
    @groupings << [range, color]
  end

  def range_to_s range
    if range.begin == range.end
      range.begin.to_s
    elsif range.end.nil?
      "#{range.begin} or more"
    elsif range.begin.nil?
      "Up to #{range.end}"
    else
      "#{range.begin}-#{range.end}"
    end
  end

  def story_points_at issue:, start_time:
    story_points = nil
    issue.changes.each do |change|
      return story_points if change.time >= start_time

      story_points = change.value if change.story_points?
    end
    story_points
  end
end
