# frozen_string_literal: true

require 'jirametrics/chart_base'
require 'jirametrics/groupable_issue_chart'
require 'jirametrics/board_movement_calculator'

class AgingWorkInProgressChart < ChartBase
  include GroupableIssueChart
  attr_accessor :possible_statuses, :board_id
  attr_reader :board_columns

  def initialize block
    super()
    header_text 'Aging Work in Progress'
    description_text <<-HTML
      <p>
        This chart shows only work items that have started but not completed, grouped by the column
        they're currently in. Hovering over a dot will show you the ID of that work item.
      </p>
      <p>
        The shaded areas indicate what percentage of the work has passed that column within that time.
        Notes:
        <ul>
          <li>It only shows columns that are considered "in progress". If you see a column that wouldn't normally
          be thought of that way, then likely issues were moving backwards or continued to progress after hitting
          that column.</li>
          <li>If you see a colour group that drops as it moves to the right, that generally indicates that
            a different number of data points is being included in each column. Probably because tickets moved
             backwards athough it could also indicate that a ticket jumped over columns as it moved to the right.
           </li>
        </ul>
      </p>
      <div style="border: 1px solid gray; padding: 0.2em">
        <% @percentiles.keys.sort.reverse.each do |percent| %>
          <span style="padding-left: 0.5em; padding-right: 0.5em; vertical-align: middle;"><%= color_block @percentiles[percent] %> <%= percent %>%</span>
        <% end %>
      </div>
    HTML
    percentiles(
      50 => '--aging-work-in-progress-chart-shading-50-color',
      85 => '--aging-work-in-progress-chart-shading-85-color',
      98 => '--aging-work-in-progress-chart-shading-98-color',
      100 => '--aging-work-in-progress-chart-shading-100-color'
    )
    show_all_columns false

    init_configuration_block(block) do
      grouping_rules do |issue, rule|
        rule.label = issue.type
        rule.color = color_for type: issue.type
      end
    end
  end

  def run
    determine_board_columns

    @header_text += " on board: #{@all_boards[@board_id].name}"
    data_sets = make_data_sets

    adjust_visibility_of_unmapped_status_column data_sets: data_sets
    adjust_chart_height

    wrap_and_render(binding, __FILE__)
  end

  def show_all_columns show = true # rubocop:disable Style/OptionalBooleanParameter
    @show_all_columns = show
  end

  def determine_board_columns
    unmapped_statuses = current_board.possible_statuses.collect(&:id)

    columns = current_board.visible_columns
    columns.each { |c| unmapped_statuses -= c.status_ids }

    @fake_column = BoardColumn.new({
      'name' => '[Unmapped Statuses]',
      'statuses' => unmapped_statuses.collect { |id| { 'id' => id.to_s } }.uniq # rubocop:disable Performance/ChainArrayAllocation
    })
    @board_columns = columns + [@fake_column]
  end

  def make_data_sets
    aging_issues = @issues.select do |issue|
      board = issue.board
      board.id == @board_id && board.cycletime.in_progress?(issue)
    end

    @max_age = 20
    rules_to_issues = group_issues aging_issues
    data_sets = rules_to_issues.keys.collect do |rules|
      {
        'type' => 'line',
        'label' => rules.label,
        'data' => rules_to_issues[rules].filter_map do |issue|
            age = issue.board.cycletime.age(issue, today: date_range.end)
            column = column_for issue: issue
            next if column.nil?

            @max_age = age if age > @max_age

            {
              'y' => age,
              'x' => column.name,
              'title' => ["#{issue.key} : #{issue.summary} (#{label_days age})"]
            }
          end,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => rules.color
      }
    end

    calculator = BoardMovementCalculator.new board: @all_boards[@board_id], issues: issues, today: date_range.end

    column_indexes_to_remove = []
    unless @show_all_columns
      column_indexes_to_remove = indexes_of_leading_and_trailing_zeros(calculator.age_data_for(percentage: 100))

      column_indexes_to_remove.reverse_each do |index|
        @board_columns.delete_at index
      end
    end

    @row_index_offset = data_sets.size

    bar_data = []
    calculator.stacked_age_data_for(percentages: @percentiles.keys).each do |percentage, data|
      column_indexes_to_remove.reverse_each { |index| data.delete_at index }
      color = @percentiles[percentage]

      data_sets << {
        'type' => 'bar',
        'label' => "#{percentage}%",
        'barPercentage' => 1.0,
        'categoryPercentage' => 1.0,
        'backgroundColor' => color,
        'data' => data
      }
      bar_data << data
    end
    @bar_data = adjust_bar_data bar_data

    data_sets
  end

  def adjust_bar_data input
    return [] if input.empty?

    row_size = input.first.size

    output = []
    output << input.first
    input.drop(1).each do |row|
      previous_row = output.last
      output << 0.upto(row_size - 1).collect { |i| row[i] + previous_row[i] }
    end

    output
  end

  def indexes_of_leading_and_trailing_zeros list
    result = []
    0.upto(list.size - 1) do |index|
      break unless list[index].zero?

      result << index
    end

    stop_at = result.empty? ? 0 : (result.last + 1)
    (list.size - 1).downto(stop_at).each do |index|
      break unless list[index].zero?

      result << index if list[index].zero?
    end
    result
  end

  def column_for issue:
    @board_columns.find do |board_column|
      board_column.status_ids.include? issue.status.id
    end
  end

  def adjust_visibility_of_unmapped_status_column data_sets:
    column_name = @fake_column.name

    has_unmapped = data_sets.any? do |set|
      set['data'].any? do |data|
        data['x'] == column_name if data.is_a? Hash
      end
    end

    if has_unmapped
      @description_text += "<p>The items shown in #{column_name.inspect} are not visible on the " \
        'board but are still active. Most likely everyone has forgotten about them.</p>'
    else
      # @column_headings.pop
      @board_columns.pop
    end
  end

  def percentiles percentile_color_hash
    @percentiles = percentile_color_hash.transform_values { |value| CssVariable[value] }
  end

  def adjust_chart_height
    min_height = @max_age * 5

    @canvas_height = min_height if min_height > @canvas_height
    @canvas_height = 400 if min_height > 400
  end
end
