# frozen_string_literal: true

require 'jirametrics/chart_base'
require 'jirametrics/groupable_issue_chart'

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
      <div>
        The #{color_block '--non-working-days-color'} shaded area indicates the 85%
        mark for work items that have passed through here; 85% of
        previous work items left this column while still inside the shaded area. Any work items above
        the shading are outliers and they are the items that you should pay special attention to.
      </div>
    HTML
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
    column_headings = @board_columns.collect(&:name)

    adjust_visibility_of_unmapped_status_column data_sets: data_sets, column_headings: column_headings

    wrap_and_render(binding, __FILE__)
  end

  def determine_board_columns
    unmapped_statuses = current_board.possible_statuses.collect(&:id)

    columns = current_board.visible_columns
    columns.each { |c| unmapped_statuses -= c.status_ids }

    @fake_column = BoardColumn.new({
      'name' => '[Unmapped Statuses]',
      'statuses' => unmapped_statuses.collect { |id| { 'id' => id.to_s } }.uniq
    })
    @board_columns = columns + [@fake_column]
  end

  def make_data_sets
    aging_issues = @issues.select do |issue|
      board = issue.board
      board.id == @board_id && board.cycletime.in_progress?(issue)
    end

    percentage = 85
    rules_to_issues = group_issues aging_issues
    data_sets = rules_to_issues.keys.collect do |rules|
      {
        'type' => 'line',
        'label' => rules.label,
        'data' => rules_to_issues[rules].filter_map do |issue|
            age = issue.board.cycletime.age(issue, today: date_range.end)
            column = column_for issue: issue
            next if column.nil?

            { 'y' => age,
              'x' => column.name,
              'title' => ["#{issue.key} : #{issue.summary} (#{label_days age})"]
            }
          end,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => rules.color
      }
    end
    data_sets << {
      'type' => 'bar',
      'label' => "#{percentage}%",
      'barPercentage' => 1.0,
      'categoryPercentage' => 1.0,
      'backgroundColor' => CssVariable['--aging-work-in-progress-chart-shading-color'],
      'data' => days_at_percentage_threshold_for_all_columns(percentage: percentage, issues: @issues).drop(1)
    }
  end

  def days_at_percentage_threshold_for_all_columns percentage:, issues:
    accumulated_status_ids_per_column.collect do |_column, status_ids|
      ages = ages_of_issues_that_crossed_column_boundary issues: issues, status_ids: status_ids
      index = ages.size * percentage / 100
      ages.sort[index.to_i] || 0
    end
  end

  def accumulated_status_ids_per_column
    accumulated_status_ids = []
    @board_columns.reverse.filter_map do |column|
      next if column == @fake_column

      accumulated_status_ids += column.status_ids
      [column.name, accumulated_status_ids.dup]
    end.reverse
  end

  def ages_of_issues_that_crossed_column_boundary issues:, status_ids:
    issues.filter_map do |issue|
      stop = issue.first_time_in_status(*status_ids)&.to_time
      start, = issue.board.cycletime.started_stopped_times(issue)

      # Skip if either it hasn't crossed the boundary or we can't tell when it started.
      next if stop.nil? || start.nil?
      next if stop < start

      (stop.to_date - start.to_date).to_i + 1
    end
  end

  def column_for issue:
    @board_columns.find do |board_column|
      board_column.status_ids.include? issue.status.id
    end
  end

  def adjust_visibility_of_unmapped_status_column data_sets:, column_headings:
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
      column_headings.pop
      @board_columns.pop
    end
  end
end
