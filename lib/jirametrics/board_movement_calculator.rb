# frozen_string_literal: true

class BoardMovementCalculator
  attr_reader :board, :issues

  def initialize board:, issues:
    @board = board
    @issues = issues.select { |issue| issue.board == board }
    @accumulated_status_ids_per_column = board.accumulated_status_ids_per_column
  end

  def stacked_age_data_for percentages:
    data_list = percentages.sort.collect do |percentage|
      # TODO: Why are we ignoring the first?
      [percentage, age_data_for(percentage: percentage).drop(1)]
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
    data = @accumulated_status_ids_per_column.collect do |_column, status_ids|
      ages = ages_of_issues_that_crossed_column_boundary status_ids: status_ids
      if ages.empty?
        result = 0
      else
        index = ((ages.size - 1) * percentage / 100).to_i
        result = ages[index]
      end
      result
    end

    ensure_numbers_always_goes_up(data)
  end

  def ages_of_issues_that_crossed_column_boundary status_ids:
    @issues.filter_map do |issue|
      stop = issue.first_time_in_status(*status_ids)&.to_time
      start, = issue.board.cycletime.started_stopped_times(issue)

      # Skip if either it hasn't crossed the boundary or we can't tell when it started.
      next if stop.nil? || start.nil?

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
end
