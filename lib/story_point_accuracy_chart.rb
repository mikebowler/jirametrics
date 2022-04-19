# frozen_string_literal: true

class StoryPointAccuracyChart < ChartBase

  def run
    data_sets = []

    data = scan_issues
    return nil if data.empty?

    color = 'blue'
    data_sets << {
      'label' => 'foo',
      'data' => data,
      'fill' => false,
      'showLine' => false,
      'backgroundColor' => color
    }
    render(binding, __FILE__)
  end

  def scan_issues
    issues.collect do |issue|
      start_time = cycletime.started_time(issue)
      stop_time = cycletime.stopped_time(issue)

      next unless start_time && stop_time

      estimate = story_points_at issue: issue, start_time: start_time
      cycle_time = (stop_time.to_date - start_time.to_date).to_i + 1

      next unless estimate

      {
        'x' => cycle_time,
        'y' => estimate,
        'title' => ["#{issue.key} : #{issue.summary} (#{label_days(cycle_time)})"]
      }
    end.compact
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
