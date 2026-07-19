# frozen_string_literal: true

class CfdDataBuilder
  def initialize board:, issues:, date_range:, columns: nil
    @board = board
    @issues = issues
    @date_range = date_range
    @columns = columns || board.visible_columns
  end

  def run
    column_map = build_column_map
    issue_states = @issues.map { |issue| process_issue(issue, column_map) }

    {
      columns: @columns.map(&:name),
      daily_counts: build_daily_counts(issue_states),
      correction_windows: issue_states.flat_map { |s| s[:correction_windows] }
    }
  end

  private

  def build_column_map
    map = {}
    @columns.each_with_index do |column, index|
      column.status_ids.each { |id| map[id] = index }
    end
    map
  end

  # Returns { high_water_mark_timeline: [[date, high_water_mark_value], ...], correction_windows: [...] }
  def process_issue issue, column_map
    start_time = issue.started_stopped_times.first
    return { high_water_mark_timeline: [], correction_windows: [] } if start_time.nil?

    high_water_mark = nil
    correction_open_since = nil
    correction_windows = []
    high_water_mark_timeline = [] # sorted chronologically by date

    issue.status_changes.each do |change|
      next if change.time < start_time

      col_index = column_map[change.value_id]
      next if col_index.nil?

      if high_water_mark.nil? || col_index > high_water_mark
        # Forward movement: advance high_water_mark, close any open correction window, record timeline entry
        if correction_open_since
          correction_windows << {
            start_date: correction_open_since,
            end_date: change.time.to_date,
            column_index: high_water_mark
          }
          correction_open_since = nil
        end
        high_water_mark = col_index
        high_water_mark_timeline << [change.time.to_date, high_water_mark]
      elsif col_index == high_water_mark && correction_open_since
        # Same-column recovery: close the correction window without changing high_water_mark or adding timeline entry
        correction_windows << {
          start_date: correction_open_since,
          end_date: change.time.to_date,
          column_index: high_water_mark
        }
        correction_open_since = nil
      elsif col_index < high_water_mark
        # Backwards movement: open correction window if not already open
        correction_open_since ||= change.time.to_date
      end
    end

    if correction_open_since
      correction_windows << {
        start_date: correction_open_since,
        end_date: @date_range.end,
        column_index: high_water_mark
      }
    end

    { high_water_mark_timeline: high_water_mark_timeline, correction_windows: correction_windows }
  end

  def high_water_mark_at high_water_mark_timeline, date
    result = nil
    high_water_mark_timeline.each do |timeline_date, high_water_mark|
      break if timeline_date > date

      result = high_water_mark
    end
    result
  end

  def build_daily_counts issue_states
    column_count = @columns.size
    @date_range.each_with_object({}) do |date, result|
      counts = Array.new(column_count, 0)
      issue_states.each do |state|
        high_water_mark = high_water_mark_at(state[:high_water_mark_timeline], date)
        next if high_water_mark.nil?

        (0..high_water_mark).each { |i| counts[i] += 1 }
      end
      result[date] = counts
    end
  end
end
