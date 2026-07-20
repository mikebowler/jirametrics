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

  # Tracks an issue's furthest progress (the high water mark) and, whenever it slips behind that mark,
  # the correction window that stays open until it recovers. Mutated in place as we walk the changes.
  CorrectionState = Struct.new(
    :high_water_mark, :correction_open_since, :correction_windows, :high_water_mark_timeline,
    keyword_init: true
  )
  private_constant :CorrectionState

  # Returns { high_water_mark_timeline: [[date, high_water_mark], ...], correction_windows: [...] }
  def process_issue issue, column_map
    start_time = issue.started_stopped_times.first
    return { high_water_mark_timeline: [], correction_windows: [] } if start_time.nil?

    state = CorrectionState.new(
      high_water_mark: nil, correction_open_since: nil, correction_windows: [], high_water_mark_timeline: []
    )
    issue.status_changes.each do |change|
      next if change.time < start_time

      col_index = column_map[change.value_id]
      next if col_index.nil?

      apply_change(state, col_index, change.time.to_date)
    end
    # A window still open at the end never recovered, so it runs to the end of the range.
    close_correction(state, @date_range.end) if state.correction_open_since

    { high_water_mark_timeline: state.high_water_mark_timeline, correction_windows: state.correction_windows }
  end

  def apply_change state, col_index, date
    if state.high_water_mark.nil? || col_index > state.high_water_mark
      advance_high_water_mark(state, col_index, date)
    elsif col_index == state.high_water_mark && state.correction_open_since
      close_correction(state, date) # recovered back to the high water mark
    elsif col_index < state.high_water_mark
      state.correction_open_since ||= date # slipped behind; open a window if one isn't already open
    end
  end

  def advance_high_water_mark state, col_index, date
    close_correction(state, date) if state.correction_open_since
    state.high_water_mark = col_index
    state.high_water_mark_timeline << [date, col_index]
  end

  def close_correction state, end_date
    state.correction_windows << {
      start_date: state.correction_open_since,
      end_date: end_date,
      column_index: state.high_water_mark
    }
    state.correction_open_since = nil
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
