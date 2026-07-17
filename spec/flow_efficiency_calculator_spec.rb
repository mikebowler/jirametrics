# frozen_string_literal: true

require './spec/spec_helper'

describe FlowEfficiencyCalculator do
  let(:board) { board_with_blocked_stalled_statuses }
  let(:settings) do
    {
      'blocked_statuses' => status_collection_for(board: board, names: %w[Blocked Blocked2]),
      'stalled_statuses' => status_collection_for(board: board, names: %w[Stalled Stalled2]),
      'stalled_threshold_days' => 5
    }
  end
  let(:seconds_per_day) { (60 * 60 * 24).to_f }

  # Mirrors Issue#flow_efficiency_numbers: resolve start/stop, guard, cap the window at the stop time,
  # build the stream, then hand it to the calculator.
  def flow_efficiency issue, end_time:, settings:
    issue_start, issue_stop = issue.started_stopped_times
    return [0.0, 0.0] if !issue_start || issue_start > end_time

    end_time = issue_stop if issue_stop && issue_stop < end_time
    FlowEfficiencyCalculator.new(
      blocked_stalled_changes: issue.blocked_stalled_changes(end_time: end_time, settings: settings),
      issue_start: issue_start,
      end_time: end_time
    ).calculate
  end

  it 'returns zeros when issue never started' do
    issue = empty_issue created: '2000-01-01', board: sample_board
    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, nil, nil]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-02'), settings: settings))
      .to eq [0, 0]
  end

  it 'is created in active status and never changed' do
    issue = empty_issue created: '2000-01-01', board: sample_board
    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, issue.created, nil]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-02'), settings: settings))
      .to eq [seconds_per_day, seconds_per_day]
  end

  it 'becomes blocked before issue starts and stays that way' do
    issue = empty_issue created: '2000-01-01', board: board
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-01T00:01:00')
    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, to_time('2000-01-02'), nil]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-03'), settings: settings))
      .to eq [seconds_per_day, seconds_per_day]
  end

  it 'becomes blocked but issue does not start before end_time' do
    issue = empty_issue created: '2000-01-01', board: board
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-01T00:01:00')
    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, to_time('2000-01-04'), nil]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-03'), settings: settings))
      .to eq [0.0, 0.0]
  end

  it 'becomes blocked after done' do
    issue = empty_issue created: '2000-01-01', board: board
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-03')
    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, to_time('2000-01-01'), to_time('2000-01-02')]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-04'), settings: settings))
      .to eq [seconds_per_day, seconds_per_day]
  end

  it 'becomes blocked and then unblocked before start' do
    issue = empty_issue created: '2000-01-01', board: board
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-02')
    add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2000-01-03')
    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, to_time('2000-01-04'), nil]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-05'), settings: settings))
      .to eq [seconds_per_day, seconds_per_day]
  end

  it 'was created in blocked status' do
    issue = empty_issue created: '2000-01-01', board: board, creation_status: ['Blocked', 10]
    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, to_time('2000-01-01'), nil]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-02'), settings: settings))
      .to eq [0.0, seconds_per_day]
  end

  it 'was created in done status' do
    issue = empty_issue created: '2000-01-01', board: board, creation_status: ['Done', 1]
    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, to_time('2000-01-01'), to_time('2000-01-01')]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-02'), settings: settings))
      .to eq [0.0, 0.0]
  end

  it 'handles complex case with multiple block/unblock' do
    issue = empty_issue created: '2000-01-01', board: board
    # active for a day here
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-02')
    add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2000-01-03')
    # active for a day here
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-04')
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-05') # 2nd blocked
    add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2000-01-06')
    # active for a day here, then issue finishes. The last two blocked should be ignored
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-09')
    add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2000-01-10')

    issue.board.cycletime = mock_cycletime_config stub_values: [
      [issue, to_time('2000-01-01'), to_time('2000-01-08')]
    ]
    expect(flow_efficiency(issue, end_time: to_time('2000-01-07'), settings: settings))
      .to eq [seconds_per_day * 3, seconds_per_day * 6]
  end
end
