# frozen_string_literal: true

require './spec/spec_helper'

describe DataQualityReport do
  let(:issue1) { load_issue('SP-1') }
  let(:issue2) { load_issue('SP-2') }
  let(:issue10) { load_issue('SP-10') }
  let(:subject) do
    subject = DataQualityReport.new
    subject.issues = [issue10, issue1]

    today = Date.parse('2021-12-17')
    block = lambda do |_|
      start_at first_status_change_after_created
      stop_at last_resolution
    end
    subject.cycletime = CycleTimeConfig.new parent_config: nil, label: 'default', block: block, today: today

    subject
  end

  it 'should create entries' do
    subject.initialize_entries

    expect(subject.testable_entries).to eq [
      ['2021-06-18T18:43:34+00:00', '', issue1],
      ['2021-08-29T18:06:28+00:00', '2021-09-06T04:34:26+00:00', issue10]
    ]

    expect(subject.entries_with_problems).to be_empty
  end

  it 'should identify items with completed but not started' do
    issue1.changes.clear
    issue1.changes << mock_change(field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
    subject.initialize_entries

    subject.scan_for_completed_issues_without_a_start_time

    expect(subject.entries_with_problems.collect { |entry| entry.issue.key }).to eq ['SP-1']
  end

  it 'should detect status changes after done' do
    # Issue 1 does have a resolution but no status after it.
    # Issue 2 has no resolutions at all
    # Issue 10 has a resolution with a status afterwards.

    issue1.changes.clear
    issue1.changes << mock_change(field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')

    subject.issues << issue2

    issue10.changes.clear
    issue10.changes << mock_change(field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
    issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-09-07T04:34:26+00:00')
    subject.initialize_entries

    subject.scan_for_status_change_after_done

    expect(subject.entries_with_problems.collect { |entry| entry.issue.key }).to eq ['SP-10']
  end

  describe 'backwards movement' do
    it 'should detect backwards status' do
      subject.board_metadata = load_complete_sample_columns
      subject.possible_statuses = load_complete_sample_statuses
      subject.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-09-05', value_id: 3)
      issue1.changes << mock_change(
        field: 'status', value: 'Selected for Development', old_value: 'In Progress',
        time: '2021-09-06', value_id: 10_001
      )

      subject.scan_for_backwards_movement entry: entry

      expect(entry.problems.size).to eq 1
      _problem, impact = *entry.problems.first
      expect(impact).to match 'Backwards movement across statuses'
    end

    it 'should detect backwards status category' do
      subject.board_metadata = load_complete_sample_columns
      subject.possible_statuses = load_complete_sample_statuses
      subject.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'Done', time: '2021-09-05', value_id: 10_002)
      issue1.changes << mock_change(
        field: 'status', value: 'In Progress', old_value: 'Done',
        time: '2021-09-06', value_id: 3
      )

      subject.scan_for_backwards_movement entry: entry

      expect(entry.problems.size).to eq 1
      _problem, impact = *entry.problems.first
      expect(impact).to match 'Backwards movement across status categories'
    end
  end
end
