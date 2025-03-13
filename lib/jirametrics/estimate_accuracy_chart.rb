# frozen_string_literal: true

class EstimateAccuracyChart < ChartBase
  def initialize configuration_block
    super()

    header_text 'Estimate Accuracy'
    description_text <<-HTML
      <div class="p">
        This chart graphs estimates against actual recorded cycle times. Since
        estimates can change over time, we're graphing the estimate at the time that the story started.
      </div>
      <div class="p">
        The #{color_block '--estimate-accuracy-chart-completed-fill-color'} completed dots indicate
        cycletimes.
        <% if @has_aging_data %>
          The #{color_block '--estimate-accuracy-chart-active-fill-color'} aging dots
          (click on the legend to turn them on) show the current
          age of items, which will give you a hint as to where they might end up. If they're already
          far to the right then you know you have a problem.
        <% end %>
      </div>
    HTML

    @y_axis_label = 'Story Point Estimates'
    @y_axis_type = 'linear'
    @y_axis_block = ->(issue, start_time) { story_points_at(issue: issue, start_time: start_time)&.to_f }
    @y_axis_sort_order = nil

    instance_eval(&configuration_block)
  end

  def run
    data_sets = scan_issues

    return '' if data_sets.empty?

    wrap_and_render(binding, __FILE__)
  end

  def scan_issues
    completed_hash, aging_hash = split_into_completed_and_aging issues: issues

    @has_aging_data = !aging_hash.empty?

    [
      [completed_hash, 'Completed', 'completed', false],
      [aging_hash, 'Still in progress', 'active', true]
    ].filter_map do |hash, label, completed_or_active, starts_hidden|
      fill_color = CssVariable["--estimate-accuracy-chart-#{completed_or_active}-fill-color"]
      border_color = CssVariable["--estimate-accuracy-chart-#{completed_or_active}-border-color"]

      # We sort so that the smaller circles are in front of the bigger circles.
      data = hash.sort(&hash_sorter).collect do |key, values|
        estimate, cycle_time = *key
        estimate_label = "#{estimate}#{'pts' if @y_axis_type == 'linear'}"
        title = ["Estimate: #{estimate_label}, Cycletime: #{label_days(cycle_time)}, #{values.size} issues"] +
          values.collect { |issue| "#{issue.key}: #{issue.summary}" }
        {
          'x' => cycle_time,
          'y' => estimate,
          'r' => values.size * 2,
          'title' => title
        }
      end
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
    end
  end

  def split_into_completed_and_aging issues:
    aging_hash = {}
    completed_hash = {}

    issues.each do |issue|
      cycletime = issue.board.cycletime
      start_time, stop_time = cycletime.started_stopped_times(issue)

      next unless start_time

      hash = stop_time ? completed_hash : aging_hash

      estimate = @y_axis_block.call issue, start_time
      cycle_time = ((stop_time&.to_date || date_range.end) - start_time.to_date).to_i + 1

      next if estimate.nil?

      key = [estimate, cycle_time]
      (hash[key] ||= []) << issue
    end

    [completed_hash, aging_hash]
  end

  def hash_sorter
    lambda do |arg1, arg2|
      estimate1 = arg1[0][0]
      estimate2 = arg2[0][0]
      sample_count1 = arg1.size
      sample_count2 = arg2.size

      if @y_axis_sort_order
        index1 = @y_axis_sort_order.index estimate1
        index2 = @y_axis_sort_order.index estimate2

        if index1.nil?
          comparison = 1
        elsif index2.nil?
          comparison = -1
        else
          comparison = index1 <=> index2
        end
        return comparison unless comparison.zero?
      end

      sample_count2 <=> sample_count1
    end
  end

  def story_points_at issue:, start_time:
    story_points = nil
    estimate_display_name = current_board.estimation_configuration.display_name

    issue.changes.each do |change|
      return story_points if change.time >= start_time

      story_points = change.value if change.field == estimate_display_name
    end
    story_points
  end

  def y_axis label:, sort_order: nil, &block
    @y_axis_sort_order = sort_order
    @y_axis_label = label
    if sort_order
      @y_axis_type = 'category'
    else
      @y_axis_type = 'linear'
    end
    @y_axis_block = block
  end
end
