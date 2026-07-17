# frozen_string_literal: true

require './spec/spec_helper'

describe BlockedStalledByDateBuilder do
  let(:board) { board_with_blocked_stalled_statuses }

  def by_date issue, date_range:, chart_end_time:
    BlockedStalledByDateBuilder.new(
      blocked_stalled_changes: issue.blocked_stalled_changes(end_time: chart_end_time),
      date_range: date_range
    ).build
  end

  it 'handles no changes' do
    issue = empty_issue created: '2021-10-01', board: board
    actual = by_date(
      issue,
      date_range: to_date('2021-10-02')..to_date('2021-10-04'),
      chart_end_time: to_time('2021-10-04T23:59:59')
    )
    expect(actual.transform_values(&:as_symbol)).to eq({
      to_date('2021-10-02') => :active,
      to_date('2021-10-03') => :active,
      to_date('2021-10-04') => :active
    })
  end

  it 'tracks blocked over multiple days' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')

    actual = by_date(
      issue,
      date_range: to_date('2021-10-02')..to_date('2021-10-04'),
      chart_end_time: to_time('2021-10-04T23:59:59')
    )
    expect(actual.transform_values(&:as_symbol)).to eq({
      to_date('2021-10-02') => :active,
      to_date('2021-10-03') => :blocked,
      to_date('2021-10-04') => :blocked
    })
  end

  it 'tracks blocked then unblocked' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
    add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')

    actual = by_date(
      issue,
      date_range: to_date('2021-10-02')..to_date('2021-10-04'),
      chart_end_time: to_time('2021-10-04T23:59:59')
    )
    expect(actual.transform_values(&:as_symbol)).to eq({
      to_date('2021-10-02') => :active,
      to_date('2021-10-03') => :blocked,
      to_date('2021-10-04') => :active
    })
  end

  it 'handles a date range that covers time before the issue starts and after it finishes' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked', time: '2021-10-02')

    actual = by_date(
      issue,
      date_range: to_date('2021-09-30')..to_date('2021-10-03'),
      chart_end_time: to_time('2021-10-04T23:59:59')
    )
    expect(actual.transform_values(&:as_symbol)).to eq({
      to_date('2021-09-30') => :active,
      to_date('2021-10-01') => :active,
      to_date('2021-10-02') => :blocked,
      to_date('2021-10-03') => :blocked
    })
  end

  it 'extrapolates the first change backward and the last change forward across the range' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked', time: '2021-10-02')

    actual = by_date(
      issue,
      date_range: to_date('2021-09-30')..to_date('2021-10-06'),
      chart_end_time: to_time('2021-10-04T23:59:59')
    )
    expect(actual.transform_values(&:as_symbol)).to eq({
      to_date('2021-09-30') => :active,  # before the first change: mirrors the first change
      to_date('2021-10-01') => :active,
      to_date('2021-10-02') => :blocked,
      to_date('2021-10-03') => :blocked, # gap day, carried forward
      to_date('2021-10-04') => :blocked,
      to_date('2021-10-05') => :blocked, # after the last change: mirrors the last change
      to_date('2021-10-06') => :blocked
    })
  end

  it 'picks the most-blocking change when several land on the same day' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-01T06:00:00')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-01T12:00:00')

    actual = by_date(
      issue,
      date_range: to_date('2021-10-01')..to_date('2021-10-01'),
      chart_end_time: to_time('2021-10-01T23:59:59')
    )
    expect(actual.transform_values(&:as_symbol)).to eq({ to_date('2021-10-01') => :blocked })
  end

  describe '#wins_the_day?' do
    let(:builder) { described_class.new(blocked_stalled_changes: [], date_range: nil) }
    let(:blocked) { BlockedStalledChange.new(flagged: 'Blocked', time: to_time('2021-10-01')) }
    let(:active) { BlockedStalledChange.new(time: to_time('2021-10-01')) }
    let(:stalled) { BlockedStalledChange.new(stalled_days: 5, time: to_time('2021-10-01')) }

    it 'lets a blocked change win over any current winner' do
      aggregate_failures do
        expect(builder.wins_the_day?(blocked, blocked)).to be true
        expect(builder.wins_the_day?(blocked, active)).to be true
        expect(builder.wins_the_day?(blocked, stalled)).to be true
      end
    end

    it 'lets an active change win only over an active or stalled winner' do
      aggregate_failures do
        expect(builder.wins_the_day?(active, blocked)).to be false
        expect(builder.wins_the_day?(active, active)).to be true
        expect(builder.wins_the_day?(active, stalled)).to be true
      end
    end

    it 'lets a stalled change win only over a stalled winner' do
      aggregate_failures do
        expect(builder.wins_the_day?(stalled, blocked)).to be false
        expect(builder.wins_the_day?(stalled, active)).to be false
        expect(builder.wins_the_day?(stalled, stalled)).to be true
      end
    end
  end

  it 'handles complex case' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-07T00:01:00')
    add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-07T00:02:00')

    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-09')
    add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-11')

    actual = by_date(
      issue,
      date_range: to_date('2021-10-01')..to_date('2021-10-12'),
      chart_end_time: to_time('2021-10-12T23:59:59')
    )
    expect(actual.transform_values(&:as_symbol)).to eq({
      to_date('2021-10-01') => :active,  # created and therefore active
      to_date('2021-10-02') => :stalled, # no activity for the next five days so start tracking stalled
      to_date('2021-10-03') => :stalled, # no change
      to_date('2021-10-04') => :stalled, # no change
      to_date('2021-10-05') => :stalled, # no change
      to_date('2021-10-06') => :stalled, # no change
      to_date('2021-10-07') => :blocked, # blocked and unblocked same day
      to_date('2021-10-08') => :active,
      to_date('2021-10-09') => :blocked, # becomes blocked
      to_date('2021-10-10') => :blocked, # No changes on this day, should still be blocked
      to_date('2021-10-11') => :active, # block cleared
      to_date('2021-10-12') => :active
    })
  end
end
