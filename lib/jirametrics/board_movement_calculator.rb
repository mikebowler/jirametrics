# frozen_string_literal: true

class BoardMovementCalculator
  attr_reader :board, :issues, :today

  def initialize board:, issues:, today:
    @board = board
    @issues = issues.select { |issue| issue.board == board }
    @today = today
  end

  def stacked_age_data_for percentages:
    data_list = percentages.sort.collect do |percentage|
      [percentage, age_data_for(percentage: percentage)]
    end

    stack_data data_list
  end

  def stack_data data_list
    remainder = nil
    data_list.collect do |percentage, data|
      unless remainder.nil?
        data = (0...data.length).collect do |i|
          data[i] - remainder[i]
        end

      end
      remainder = data

      [percentage, data]
    end
  end

  def age_data_for percentage:
    data = []
    board.visible_columns.each_with_index do |_column, column_index|
      ages = ages_of_issues_when_leaving_column column_index: column_index, today: today
      if ages.empty?
        data << 0
      else
        index = ((ages.size - 1) * percentage / 100).to_i
        data << ages[index]
      end
    end
    ensure_numbers_always_goes_up(data)
  end

  def ages_of_issues_when_leaving_column column_index:, today:
    next_column = board.visible_columns[column_index + 1]

    @issues.filter_map do |issue|
      stop = next_column.nil? ? nil : issue.first_time_in_or_right_of_column(next_column.name)&.time
      start, = issue.board.cycletime.started_stopped_times(issue)

      # Skip if we can't tell when it started.
      next if start.nil?

      # If we haven't left this column yet, use current age
      next (today - start.to_date).to_i + 1 if stop.nil?

      # Skip if it left this column before the item is considered started.
      next if stop <= start

      (stop.to_date - start.to_date).to_i + 1
    end.sort
  end

  def ensure_numbers_always_goes_up data
    # There's an odd exception where we want to leave zeros at the end of the line alone.
    reversed_index = data.reverse.index { |number| !number.zero? }
    return data if reversed_index.nil?

    last_non_zero = data.length - reversed_index

    # It's possible for a column to the right to have a lower number if the ticket skipped columns. Adjust for that
    # so that numbers are always increasing.
    (1...last_non_zero).each do |i|
      data[i] = [data[i], data[i - 1]].max
    end
    data
  end

  # Figure out what column this is issue is currently in and what time it entered that column. We need this for
  # aging and forecasting purposes
  def find_current_column_and_entry_time_in_column issue
    column = board.visible_columns.find { |c| c.status_ids.include?(issue.status.id) }
    if column.nil?
      message = "Issue #{issue.key} is in status #{issue.status}. Can't find that status on the board with columns: "
      board.visible_columns.each do |column|
        message << column.name << '('
        message << column.status_ids.collect do |id|
          board.possible_statuses.find_by_id(id)
        end.join(', ')
        message << '), '
      end
      message << "\nIssue has changes"
      issue.changes.each do |change|
        message << "\n  " << change.to_s
      end
      puts message
    end
    return [] if column.nil? # This issue isn't visible on the board

    status_ids = column.status_ids

    entry_at = issue.changes.reverse.find { |change| change.status? && status_ids.include?(change.value_id) }&.time

    [column.name, entry_at]
  end

  def label_days days
    "#{days} day#{'s' unless days == 1}"
  end

  def forecasted_days_remaining_and_message issue:, today:
    likely_age_data = age_data_for percentage: 85

    column_name, entry_time = find_current_column_and_entry_time_in_column issue
    return [nil, 'This issue is not visible on the board. No way to predict when it will be done.'] if column_name.nil?

    age_in_column = (today - entry_time.to_date).to_i + 1

    message = nil
    column_index = board.visible_columns.index { |c| c.name == column_name }

    last_non_zero_datapoint = likely_age_data.reverse.find { |d| !d.zero? }
    remaining_in_current_column = likely_age_data[column_index] - age_in_column
    if remaining_in_current_column.negative?
      message = "This item is an outlier; at #{label_days issue.board.cycletime.age(issue)}, " \
        "it's already taking longer than most items so we cannot forecast when it will be done."
      remaining_in_current_column = 0
    end

    return [nil, 'There is no historical data for this board. No forecast can be made.'] if last_non_zero_datapoint.nil?

    forecasted_days = last_non_zero_datapoint - likely_age_data[column_index] + remaining_in_current_column

    [forecasted_days, message]
  end
end
