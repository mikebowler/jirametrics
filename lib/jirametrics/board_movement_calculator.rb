# frozen_string_literal: true

class BoardMovementCalculator
  attr_reader :board, :issues, :today

  def initialize board:, issues:, today:
    @board = board
    @issues = issues.select { |issue| issue.board == board && issue.done? && !moves_backwards?(issue) }
    @today = today
  end

  def moves_backwards? issue
    started, stopped = issue.board.cycletime.started_stopped_times(issue)
    return false unless started

    previous_column = nil
    issue.status_changes.each do |change|
      column = board.visible_columns.index { |c| c.status_ids.include?(change.value_id) }
      next if change.time < started
      next if column.nil? # It disappeared from the board for a bit
      return true if previous_column && column && column < previous_column

      previous_column = column
    end
    false
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
    data
  end

  def ages_of_issues_when_leaving_column column_index:, today:
    this_column = board.visible_columns[column_index]
    next_column = board.visible_columns[column_index + 1]

    @issues.filter_map do |issue|
      this_column_start = issue.first_time_in_or_right_of_column(this_column.name)&.time
      next_column_start = next_column.nil? ? nil : issue.first_time_in_or_right_of_column(next_column.name)&.time
      issue_start, issue_done = issue.board.cycletime.started_stopped_times(issue)

      # Skip if we can't tell when it started.
      next if issue_start.nil?

      # Skip if it never entered this column
      next if this_column_start.nil?

      # Skip if it left this column before the item is considered started.
      next if next_column_start && next_column_start <= issue_start

      # Skip if it was already done by the time it got to this column or it became done when it got to this column
      next if issue_done && issue_done <= this_column_start

      end_date = case # rubocop:disable Style/EmptyCaseCondition
      when next_column_start.nil?
        # If this is the last column then base age against today
        today
      when issue_done && issue_done < next_column_start
        # it completed while in this column
        issue_done.to_date
      else
        # It passed through this whole column
        next_column_start.to_date
      end
      (end_date - issue_start.to_date).to_i + 1
    end.sort
  end

  # Figure out what column this is issue is currently in and what time it entered that column. We need this for
  # aging and forecasting purposes
  def find_current_column_and_entry_time_in_column issue
    column = board.visible_columns.find { |c| c.status_ids.include?(issue.status.id) }
    return [] if column.nil? # This issue isn't visible on the board

    status_ids = column.status_ids

    entry_at = issue.changes.reverse.find { |change| change.status? && status_ids.include?(change.value_id) }&.time

    [column.name, entry_at]
  end

  def label_days days
    "#{days} day#{'s' unless days == 1}"
  end

  def forecasted_days_remaining_and_message issue:, today:
    return [nil, 'Already done'] if issue.done?

    likely_age_data = age_data_for percentage: 85

    column_name, entry_time = find_current_column_and_entry_time_in_column issue
    return [nil, 'This issue is not visible on the board. No way to predict when it will be done.'] if column_name.nil?

    age_in_column = (today - entry_time.to_date).to_i + 1

    message = nil
    column_index = board.visible_columns.index { |c| c.name == column_name }

    last_non_zero_datapoint = likely_age_data.reverse.find { |d| !d.zero? }
    return [nil, 'There is no historical data for this board. No forecast can be made.'] if last_non_zero_datapoint.nil?

    remaining_in_current_column = likely_age_data[column_index] - age_in_column
    if remaining_in_current_column.negative?
      message = "This item is an outlier at #{label_days issue.board.cycletime.age(issue, today: today)} " \
        "in the #{column_name.inspect} column. Most items on this board have left this column in " \
        "#{label_days likely_age_data[column_index]} or less, so we cannot forecast when it will be done."
      remaining_in_current_column = 0
    end

    forecasted_days = last_non_zero_datapoint - likely_age_data[column_index] + remaining_in_current_column
    [forecasted_days, message]
  end
end
