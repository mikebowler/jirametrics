# spec/cfd_data_builder_spec.rb
# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cfd_data_builder'

describe CfdDataBuilder do
  let(:board) { sample_board }
  let(:date_range) { Date.parse('2021-07-01')..Date.parse('2021-07-10') }

  def build(**overrides)
    defaults = { board: board, issues: [], date_range: date_range }
    CfdDataBuilder.new(**defaults, **overrides).run
  end

  context 'columns' do
    it 'returns visible column names in left-to-right order' do
      expect(build[:columns]).to eq ['Ready', 'In Progress', 'Review', 'Done']
    end
  end

  context 'daily_counts' do
    it 'returns zero counts when no issues are on the board' do
      expect(build[:daily_counts][Date.parse('2021-07-05')]).to eq [0, 0, 0, 0]
    end

    it 'counts cumulative totals per column across all dates' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'Selected for Development',
        value_id: 10_001, time: '2021-07-02T10:00:00')

      issue2 = empty_issue(created: '2021-07-01', key: 'SP-2')
      add_mock_change(issue: issue2, field: 'status', value: 'In Progress', value_id: 3, time: '2021-07-03T10:00:00')

      result = build(issues: [issue1, issue2])

      # July 1: no issues have reached any column yet
      expect(result[:daily_counts][Date.parse('2021-07-01')]).to eq [0, 0, 0, 0]
      # July 2: issue1 reached Ready (col 0); cumulative: col0+=1
      expect(result[:daily_counts][Date.parse('2021-07-02')]).to eq [1, 0, 0, 0]
      # July 3: issue2 reached In Progress (col 1); cumulative: col0+=2, col1+=1
      expect(result[:daily_counts][Date.parse('2021-07-03')]).to eq [2, 1, 0, 0]
      # July 10: same as July 3 (no more changes)
      expect(result[:daily_counts][Date.parse('2021-07-10')]).to eq [2, 1, 0, 0]
    end

    it 'returns exactly one key per day in date_range' do
      result = build(date_range: Date.parse('2021-07-05')..Date.parse('2021-07-05'))
      expect(result[:daily_counts].keys).to eq [Date.parse('2021-07-05')]
    end
  end

  context 'correction_windows' do
    it 'records a window when an issue moves backwards and recovers' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      # Reaches Review (col 2), drops to In Progress (col 1), recovers to Review (col 2)
      add_mock_change(issue: issue1, field: 'status', value: 'Review',
        value_id: 10_011, time: '2021-07-02T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress',
        value_id: 3, time: '2021-07-04T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'Review',
        value_id: 10_011, time: '2021-07-06T10:00:00')

      result = build(issues: [issue1])

      expect(result[:correction_windows].size).to eq 1
      window = result[:correction_windows].first
      expect(window[:start_date]).to eq Date.parse('2021-07-04')
      expect(window[:end_date]).to eq Date.parse('2021-07-06')
      expect(window[:column_index]).to eq 2 # Review is column index 2
    end

    it 'sets end_date to date_range.end when issue never recovers' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'Review',
        value_id: 10_011, time: '2021-07-02T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress',
        value_id: 3, time: '2021-07-04T10:00:00')

      result = build(issues: [issue1])

      expect(result[:correction_windows].first[:end_date]).to eq date_range.end
    end

    it 'records one correction window for multiple consecutive backwards moves' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'Review',
        value_id: 10_011, time: '2021-07-02T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress',
        value_id: 3, time: '2021-07-04T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'Selected for Development',
        value_id: 10_001, time: '2021-07-05T10:00:00')

      result = build(issues: [issue1])

      expect(result[:correction_windows].size).to eq 1
      expect(result[:correction_windows].first[:start_date]).to eq Date.parse('2021-07-04')
    end

    it 'returns empty correction_windows when there are no backwards moves' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'Selected for Development',
        value_id: 10_001, time: '2021-07-02T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'Done',
        value_id: 10_002, time: '2021-07-05T10:00:00')

      result = build(issues: [issue1])

      expect(result[:correction_windows]).to be_empty
    end
  end

  context 'edge cases' do
    it 'skips status changes not mapped to any board column' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      # Status ID 10000 is Backlog — not in visible_columns for this kanban board
      add_mock_change(issue: issue1, field: 'status', value: 'Backlog',
        value_id: 10_000, time: '2021-07-02T10:00:00')

      result = build(issues: [issue1])

      expect(result[:daily_counts][Date.parse('2021-07-02')]).to eq [0, 0, 0, 0]
    end

    it 'counts issues with changes before date_range in the initial snapshot' do
      issue1 = empty_issue(created: '2021-06-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2021-06-15T10:00:00')

      result = build(issues: [issue1])

      # issue1 already in In Progress (col 1) before the range starts — counts col 0 and col 1
      expect(result[:daily_counts][Date.parse('2021-07-01')]).to eq [1, 1, 0, 0]
    end

    it 'contributes 0 to all columns for an issue with no status changes' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')

      result = build(issues: [issue1])

      expect(result[:daily_counts][Date.parse('2021-07-05')]).to eq [0, 0, 0, 0]
    end

    it 'counts all columns when an issue skips directly to the rightmost column' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      # Jumps straight to Done (col 3), skipping Ready, In Progress, Review
      add_mock_change(issue: issue1, field: 'status', value: 'Done',
        value_id: 10_002, time: '2021-07-02T10:00:00')

      result = build(issues: [issue1])

      expect(result[:daily_counts][Date.parse('2021-07-02')]).to eq [1, 1, 1, 1]
    end
  end

  context 'columns: override' do
    it 'uses the provided columns instead of board.visible_columns' do
      # Pass only the first two columns (Ready, In Progress); Done and Review are excluded
      two_columns = board.visible_columns.first(2)
      result = build(columns: two_columns)
      expect(result[:columns]).to eq ['Ready', 'In Progress']
    end

    it 'does not track issues that reach an excluded column' do
      two_columns = board.visible_columns.first(2) # Ready (10001), In Progress (3)
      issue = empty_issue(created: '2021-07-01', key: 'SP-1')
      # Issue goes straight to Review (10011), which is not in the two-column set
      add_mock_change(issue: issue, field: 'status', value: 'Review',
        value_id: 10_011, time: '2021-07-02T10:00:00')
      result = build(columns: two_columns, issues: [issue])
      # Issue's status_id 10011 not in column_map → high-water-mark stays nil → not counted
      expect(result[:daily_counts][Date.parse('2021-07-05')]).to eq [0, 0]
    end
  end
end
