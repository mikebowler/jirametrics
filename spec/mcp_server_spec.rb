# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/mcp_server'

describe McpServer do
  # Board from the complete sample: Ready(10001), In Progress(3), Review(10011), Done(10002).
  let(:board) { load_complete_sample_board }

  describe '.resolve_projects' do
    it 'returns nil (no filter) when no project is given' do
      expect(described_class.resolve_projects({ aggregates: {} }, nil)).to be_nil
    end

    it 'wraps a plain project name in a one-element allow-list' do
      expect(described_class.resolve_projects({ aggregates: {} }, 'SP')).to eq ['SP']
    end

    it 'expands an aggregate name to its constituent projects' do
      context = { aggregates: { 'Everything' => %w[SP FOO] } }
      expect(described_class.resolve_projects(context, 'Everything')).to eq %w[SP FOO]
    end

    it 'treats a missing aggregates key as no aggregates' do
      expect(described_class.resolve_projects({}, 'SP')).to eq ['SP']
    end
  end

  # time_per_status/column only read a handful of methods off the issue, so drive them with
  # controlled doubles. One day = 86_400 seconds.
  def fake_status name, id: nil
    Data.define(:name, :id).new(name:, id:)
  end

  def fake_change time:, value: nil, value_id: nil, old_value: nil, old_value_id: nil
    Data.define(:time, :value, :value_id, :old_value, :old_value_id)
      .new(time: to_time(time), value:, value_id:, old_value:, old_value_id:)
  end

  def fake_issue created:, status:, changes: [], stopped: nil, issue_board: nil
    Data.define(:status_changes, :started_stopped_times, :created, :status, :board).new(
      status_changes: changes, started_stopped_times: [nil, stopped && to_time(stopped)],
      created: to_time(created), status:, board: issue_board
    )
  end

  describe '.time_per_status' do
    def time_per_status issue, end_time
      described_class.time_per_status(issue, to_time(end_time))
    end

    it 'puts the whole span in the current status when there are no changes' do
      issue = fake_issue created: '2024-01-01', status: fake_status('To Do')
      expect(time_per_status(issue, '2024-01-11')).to eq({ 'To Do' => 864_000.0 }) # 10 days
    end

    it 'records nothing when a change-less issue was created at the end time' do
      issue = fake_issue created: '2024-01-11', status: fake_status('To Do')
      expect(time_per_status(issue, '2024-01-11')).to eq({})
    end

    it 'splits the span across the pre-first, between, and final statuses' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Review'),
        changes: [
          fake_change(time: '2024-01-03', value: 'In Progress', old_value: 'To Do'),
          fake_change(time: '2024-01-06', value: 'Review', old_value: 'In Progress')
        ]
      )
      expect(time_per_status(issue, '2024-01-11')).to eq(
        'To Do' => 172_800.0,        # created -> first change (2 days), from old_value
        'In Progress' => 259_200.0,  # between changes (3 days), from prev value
        'Review' => 432_000.0        # last change -> end (5 days), from last value
      )
    end

    it 'ends the final span at the stop time when the issue stopped before the end time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Done'), stopped: '2024-01-05',
        changes: [fake_change(time: '2024-01-03', value: 'Done', old_value: 'To Do')]
      )
      expect(time_per_status(issue, '2024-01-11')).to eq(
        'To Do' => 172_800.0, 'Done' => 172_800.0 # final span ends at stop (01-03 -> 01-05), not end
      )
    end

    it 'ends the final span at the end time when the issue stopped after it' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Done'), stopped: '2024-01-20',
        changes: [fake_change(time: '2024-01-03', value: 'Done', old_value: 'To Do')]
      )
      expect(time_per_status(issue, '2024-01-11')).to eq(
        'To Do' => 172_800.0, 'Done' => 691_200.0 # final span capped at end (01-03 -> 01-11)
      )
    end

    it 'skips zero-length spans' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('In Progress'),
        changes: [fake_change(time: '2024-01-01', value: 'In Progress', old_value: 'To Do')]
      )
      expect(time_per_status(issue, '2024-01-06')).to eq({ 'In Progress' => 432_000.0 }) # no 'To Do'
    end

    it 'skips a zero-length span between two changes at the same time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('B'),
        changes: [
          fake_change(time: '2024-01-03', value: 'A', old_value: 'To Do'),
          fake_change(time: '2024-01-03', value: 'B', old_value: 'A') # same instant -> 'A' gets nothing
        ]
      )
      expect(time_per_status(issue, '2024-01-06')).to eq('To Do' => 172_800.0, 'B' => 259_200.0)
    end

    it 'skips the final span when the last change lands on the end time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('A'),
        changes: [fake_change(time: '2024-01-03', value: 'A', old_value: 'To Do')]
      )
      expect(time_per_status(issue, '2024-01-03')).to eq({ 'To Do' => 172_800.0 }) # no 'A'
    end
  end

  describe '.time_per_column' do
    def time_per_column issue, end_time
      described_class.time_per_column(issue, to_time(end_time))
    end

    it 'maps each span to its board column via the status id' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Review', id: 10_011), issue_board: board,
        changes: [
          fake_change(time: '2024-01-03', value_id: 3, old_value_id: 10_001),
          fake_change(time: '2024-01-06', value_id: 10_011, old_value_id: 3)
        ]
      )
      expect(time_per_column(issue, '2024-01-11')).to eq(
        'Ready' => 172_800.0,        # old_value_id 10001 -> Ready
        'In Progress' => 259_200.0,  # prev value_id 3 -> In Progress
        'Review' => 432_000.0        # last value_id 10011 -> Review
      )
    end

    it 'falls back to the raw status value when the id maps to no column' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Elsewhere', id: 999_999), issue_board: board,
        changes: []
      )
      expect(time_per_column(issue, '2024-01-11')).to eq({ 'Elsewhere' => 864_000.0 })
    end

    it 'records nothing when a change-less issue was created at the end time' do
      issue = fake_issue created: '2024-01-11', status: fake_status('x', id: 3), issue_board: board
      expect(time_per_column(issue, '2024-01-11')).to eq({})
    end

    it 'uses the status id (not the whole status) to look up a change-less column' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Ignored Name', id: 3), issue_board: board, changes: []
      )
      expect(time_per_column(issue, '2024-01-11')).to eq({ 'In Progress' => 864_000.0 }) # id 3 -> In Progress
    end

    it 'falls back to raw values at every position when ids map to no column' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('x', id: 666_666), issue_board: board,
        changes: [
          fake_change(time: '2024-01-03', value: 'MidS', value_id: 999_999, old_value: 'InitS', old_value_id: 888_888),
          fake_change(time: '2024-01-06', value: 'FinalS', value_id: 777_777, old_value: 'MidS', old_value_id: 999_999)
        ]
      )
      expect(time_per_column(issue, '2024-01-11')).to eq(
        'InitS' => 172_800.0, 'MidS' => 259_200.0, 'FinalS' => 432_000.0
      )
    end

    it 'skips a zero-length span between two changes at the same time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('r', id: 10_011), issue_board: board,
        changes: [
          fake_change(time: '2024-01-03', value_id: 3, old_value_id: 10_001),
          fake_change(time: '2024-01-03', value_id: 10_011, old_value_id: 3) # same instant -> In Progress gets nothing
        ]
      )
      expect(time_per_column(issue, '2024-01-06')).to eq('Ready' => 172_800.0, 'Review' => 259_200.0)
    end

    it 'skips the final span when the last change lands on the end time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('ip', id: 3), issue_board: board,
        changes: [fake_change(time: '2024-01-03', value_id: 3, old_value_id: 10_001)]
      )
      expect(time_per_column(issue, '2024-01-03')).to eq({ 'Ready' => 172_800.0 }) # no In Progress
    end

    it 'ends the final span at the stop time when the issue stopped before the end time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('d', id: 10_002), issue_board: board, stopped: '2024-01-05',
        changes: [fake_change(time: '2024-01-03', value_id: 10_002, old_value_id: 10_001)]
      )
      expect(time_per_column(issue, '2024-01-11')).to eq('Ready' => 172_800.0, 'Done' => 172_800.0) # 01-03->01-05
    end

    it 'ends the final span at the end time when the issue stopped after it' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('d', id: 10_002), issue_board: board, stopped: '2024-01-20',
        changes: [fake_change(time: '2024-01-03', value_id: 10_002, old_value_id: 10_001)]
      )
      expect(time_per_column(issue, '2024-01-11')).to eq('Ready' => 172_800.0, 'Done' => 691_200.0) # 01-03->01-11
    end

    it 'skips a zero-length initial span' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('ip', id: 3), issue_board: board,
        changes: [fake_change(time: '2024-01-01', value_id: 3, old_value_id: 10_001)] # change at creation
      )
      expect(time_per_column(issue, '2024-01-06')).to eq({ 'In Progress' => 432_000.0 }) # no Ready
    end
  end

  describe '.column_name_for' do
    it 'returns the visible column that owns the status id' do
      expect(described_class.column_name_for(board, 3)).to eq 'In Progress'
    end

    it 'returns nil when no visible column owns the status id' do
      expect(described_class.column_name_for(board, 999_999)).to be_nil
    end
  end

  describe '.matches_blocked_stalled?' do
    # bsc entries only need to answer blocked?/stalled?
    def change blocked: false, stalled: false
      Struct.new(:is_blocked, :is_stalled) do
        def blocked? = is_blocked
        def stalled? = is_stalled
      end.new(blocked, stalled)
    end

    def matches? bsc, ever_blocked: nil, ever_stalled: nil, currently_blocked: nil, currently_stalled: nil
      McpServer.matches_blocked_stalled?(bsc, ever_blocked, ever_stalled, currently_blocked, currently_stalled)
    end

    it 'matches everything when no blocked/stalled filter is set' do
      expect(matches?([])).to be true
    end

    it 'ever_blocked requires at least one blocked entry' do
      aggregate_failures do
        expect(matches?([change(blocked: true)], ever_blocked: true)).to be true
        expect(matches?([change(blocked: false)], ever_blocked: true)).to be false
        expect(matches?([], ever_blocked: true)).to be false
      end
    end

    it 'ever_stalled requires at least one stalled entry' do
      aggregate_failures do
        expect(matches?([change(stalled: true)], ever_stalled: true)).to be true
        expect(matches?([change(stalled: false)], ever_stalled: true)).to be false
      end
    end

    it 'currently_blocked requires the LAST entry to be blocked' do
      aggregate_failures do
        expect(matches?([change(blocked: false), change(blocked: true)], currently_blocked: true)).to be true
        expect(matches?([change(blocked: true), change(blocked: false)], currently_blocked: true)).to be false
        expect(matches?([], currently_blocked: true)).to be false # last is nil
      end
    end

    it 'currently_stalled requires the LAST entry to be stalled' do
      aggregate_failures do
        expect(matches?([change(stalled: true)], currently_stalled: true)).to be true
        expect(matches?([change(stalled: false)], currently_stalled: true)).to be false
        expect(matches?([], currently_stalled: true)).to be false # last is nil
      end
    end
  end

  describe '.flow_efficiency_percent' do
    def flow active, total
      time = to_time('2024-01-01')
      issue = instance_double(Issue)
      allow(issue).to receive(:flow_efficiency_numbers).with(end_time: time).and_return([active, total])
      described_class.flow_efficiency_percent(issue, time)
    end

    it 'returns active/total as a percentage rounded to one decimal' do
      expect(flow(1.0, 3.0)).to eq 33.3 # 1/3 * 100, rounded to 1dp (not 33, not 33.33)
    end

    it 'returns nil when there is no total time' do
      aggregate_failures do
        expect(flow(0.0, 0.0)).to be_nil   # zero
        expect(flow(1.0, -1.0)).to be_nil  # negative
      end
    end
  end

  describe '.matches_history?' do
    def hist_change field:, value:
      Data.define(:field, :value).new(field:, value:)
    end

    def bsc_change blocked: false, stalled: false
      Struct.new(:is_blocked, :is_stalled) do
        def blocked? = is_blocked
        def stalled? = is_stalled
      end.new(blocked, stalled)
    end

    def matches? changes: [], bsc: [], **flags
      time = to_time('2024-01-01')
      issue = instance_double(Issue, changes: changes)
      allow(issue).to receive(:blocked_stalled_changes).with(end_time: time).and_return(bsc)
      described_class.matches_history?(
        issue, time,
        flags[:history_field], flags[:history_value],
        flags[:ever_blocked], flags[:ever_stalled], flags[:currently_blocked], flags[:currently_stalled]
      )
    end

    it 'matches when no filters are set' do
      expect(matches?).to be true
    end

    it 'applies the history filter only when both a field and a value are given' do
      aggregate_failures do
        expect(matches?(history_field: 'priority')).to be true # value missing -> filter skipped
        expect(matches?(history_value: 'High')).to be true     # field missing -> filter skipped
      end
    end

    it 'requires some change to have matched the history field AND value' do
      matching = [hist_change(field: 'priority', value: 'High')]
      aggregate_failures do
        expect(matches?(changes: matching, history_field: 'priority', history_value: 'High')).to be true
        expect(matches?(changes: matching, history_field: 'priority', history_value: 'Low')).to be false # value
        expect(matches?(changes: matching, history_field: 'status', history_value: 'High')).to be false  # field
        expect(matches?(changes: [], history_field: 'priority', history_value: 'High')).to be false
      end
    end

    it 'delegates to the blocked/stalled predicate when any blocked/stalled flag is set' do
      # each flag independently enters the block, so each arm of the || guard is exercised
      aggregate_failures do
        expect(matches?(bsc: [bsc_change(blocked: true)], ever_blocked: true)).to be true
        expect(matches?(bsc: [bsc_change(blocked: false)], ever_blocked: true)).to be false
        expect(matches?(bsc: [bsc_change(stalled: true)], ever_stalled: true)).to be true
        expect(matches?(bsc: [bsc_change(stalled: false)], ever_stalled: true)).to be false
        expect(matches?(bsc: [bsc_change(blocked: true)], currently_blocked: true)).to be true
        expect(matches?(bsc: [bsc_change(blocked: false)], currently_blocked: true)).to be false
        expect(matches?(bsc: [bsc_change(stalled: true)], currently_stalled: true)).to be true
        expect(matches?(bsc: [bsc_change(stalled: false)], currently_stalled: true)).to be false
      end
    end
  end
end
