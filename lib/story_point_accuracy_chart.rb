# frozen_string_literal: true

class StoryPointAccuracyChart < ChartBase
  def initialize configuration_block = nil
    super()

    header_text 'Story Point Accuracy'
    description_text <<-HTML
      <p>
        This chart graphs story point estimates against actual recorded cycle times. Since story point
        estimates can change over time, we're graphing the estimate at the time that the story started.
      </p>
      <p>
        The blue dots indicate completed cycletimes. The red dots (if you turn them on) show where aging
        items currently are. Aging dots will give you an idea of where items may end up but aren't
        conclusive as they're still moving.
      </p>
    HTML

    instance_eval(&configuration_block) if configuration_block
  end

  def run
    data_sets = scan_issues

    return "<h1>#{@header_text}</h1>None of the items have story points. Nothing to show." if data_sets.empty?

    wrap_and_render(binding, __FILE__)
  end

  def scan_issues
    aging_hash = {}
    completed_hash = {}

    issues.each do |issue|
      cycletime = issue.board.cycletime
      start_time = cycletime.started_time(issue)
      stop_time = cycletime.stopped_time(issue)

      next unless start_time

      hash = stop_time ? completed_hash : aging_hash

      estimate = story_points_at issue: issue, start_time: start_time
      cycle_time = ((stop_time&.to_date || date_range.end) - start_time.to_date).to_i + 1

      next if estimate.nil? || estimate.empty?

      key = [estimate.to_f, cycle_time]
      (hash[key] ||= []) << issue
    end

    [
      [completed_hash, 'Completed', '#AFEEEE', 'blue', false],
      [aging_hash, 'Still in progress', '#FFCCCB', 'red', true]
    ].collect do |hash, label, fill_color, border_color, starts_hidden|
      data = hash.collect do |key, values|
        estimate, cycle_time = *key
        title = ["Estimate: #{estimate}pts, Cycletime: #{label_days(cycle_time)}, #{values.size} issues"] +
          values.collect { |issue| "#{issue.key}: #{issue.summary}" }
        {
          'x' => cycle_time,
          'y' => estimate,
          'r' => values.size * 2,
          'title' => title
        }
      end.compact
      next if data.empty?

      {
        'label' => label,
        'data' => data,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => fill_color,
        'borderColor' => border_color,
        'hidden' => starts_hidden
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

  def grouping range:, color: # rubocop:disable Lint/UnusedMethodArgument
    deprecated message: 'The grouping declaration is no longer supported on the StoryPointEstimateChart ' \
      'as we now use a bubble chart rather than colors'
  end
end
