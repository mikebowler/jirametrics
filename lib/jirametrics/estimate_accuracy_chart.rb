# frozen_string_literal: true

class EstimateAccuracyChart < ChartBase
  def initialize configuration_block
    super()

    header_text 'Estimate Accuracy'
    description_text <<~HTML
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
      <% if @correlation_coefficient %>
        <div class="p">
          The completed items here have a correlation coefficient of <b><%= @correlation_coefficient.round(3) %></b>.
          The closer it is to +1, the stronger the positive correlation. The closer it is to -1,
          the stronger the negative collalation. Zero would mean no correlation at all.
        </div>
      <% end %>
    HTML

    @x_axis_title = 'Cycletime (days)'
    @y_axis_title = 'Count of items'

    @y_axis_type = 'linear'
    @y_axis_block = ->(issue, start_time) { estimate_at(issue: issue, start_time: start_time)&.to_f }
    @y_axis_sort_order = nil

    instance_eval(&configuration_block)
  end

  def run
    if @y_axis_title.nil?
      text = current_board.estimation_configuration.units == :story_points ? 'Story Points' : 'Days'
      @y_axis_title = "Estimated #{text}"
    end
    data_sets = scan_issues

    return '' if data_sets.empty?

    wrap_and_render(binding, __FILE__)
  end

  def scan_issues
    completed_hash, aging_hash = split_into_completed_and_aging issues: issues
    @correlation_coefficient = correlation_coefficient(completed_hash) unless completed_hash.empty?
    estimation_units = current_board.estimation_configuration.units
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

        title = [
          "Estimate: #{estimate_label(estimate: estimate, estimation_units: estimation_units)}, " \
            "Cycletime: #{label_days(cycle_time)}, " \
            "#{values.size} issues"
        ] + values.collect { |issue| "#{issue.key}: #{issue.summary}" }

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

  def estimate_label estimate:, estimation_units:
    if @y_axis_type == 'linear'
      if estimation_units == :story_points
        estimate_label = "#{estimate}pts"
      elsif estimation_units == :seconds
        estimate_label = label_days estimate
      end
    end
    estimate_label = estimate.to_s if estimate_label.nil?
    estimate_label
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

  def estimate_at issue:, start_time:, estimation_configuration: current_board.estimation_configuration
    estimate = nil

    issue.changes.each do |change|
      return estimate if change.time >= start_time

      if change.field == estimation_configuration.display_name || change.field == estimation_configuration.field_id
        estimate = change.value
        estimate = estimate.to_f / (24 * 60 * 60) if estimation_configuration.units == :seconds
      end
    end
    estimate
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

  # Correlation coefficient is calculated using the Pearson Correlation Coefficient
  # r = Σ((xi - x̄)(yi - ȳ)) / sqrt(Σ(xi - x̄)² · Σ(yi - ȳ)²)
  def correlation_coefficient completed_hash
    list1 = []
    list2 = []
    completed_hash.each do |(estimate, cycle_time), issues|
      issues.size.times do
        list1 << estimate
        list2 << cycle_time
      end
    end

    n = list1.size
    return nil if n < 2

    mean1 = list1.sum.to_f / n
    mean2 = list2.sum.to_f / n

    numerator = list1.zip(list2).sum { |x, y| (x - mean1) * (y - mean2) }
    sum_sq1 = list1.sum { |x| (x - mean1)**2 }
    sum_sq2 = list2.sum { |y| (y - mean2)**2 }

    denominator = Math.sqrt(sum_sq1 * sum_sq2)
    return nil if denominator.zero?

    numerator / denominator
  end
end
