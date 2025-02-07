# frozen_string_literal: true

class BoardMovementCalculator
  attr_reader :board, :issues

  def initialize board:, issues:
    @board = board
    @issues = issues.select { |issue| issue.board == board }
    @accumulated_status_ids_per_column = board.accumulated_status_ids_per_column
  end

  def stacked_age_data_for percentages:
    remainder = nil
    percentages.sort.collect do |percentage|
      data = age_data_for(percentage: percentage).drop(1)

      unless remainder.nil?
        data = (0...data.length).collect do |i|
          data[i] - remainder[i]
        end

        # It's possible for a column to the right to have a lower number if the ticket skipped columns. Adjust for that
        # so that numbers are always increasing.
        data = (0...data.length).collect do |i|
          if i.zero?
            data[i]
          else
            [data[i], data[i - 1]].max
          end
        end
      end
      remainder = data

      [percentage, data]
    end
  end

  def age_data_for percentage:
    @accumulated_status_ids_per_column.collect do |_column, status_ids|
      ages = ages_of_issues_that_crossed_column_boundary status_ids: status_ids
      index = ages.size * percentage / 100
      ages.sort[index.to_i] || 0
    end
  end

  def ages_of_issues_that_crossed_column_boundary status_ids:
    @issues.filter_map do |issue|
      stop = issue.first_time_in_status(*status_ids)&.to_time
      start, = issue.board.cycletime.started_stopped_times(issue)

      # Skip if either it hasn't crossed the boundary or we can't tell when it started.
      next if stop.nil? || start.nil?
      next if stop < start

      (stop.to_date - start.to_date).to_i + 1
    end
  end
end
