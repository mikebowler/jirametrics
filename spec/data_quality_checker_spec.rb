# frozen_string_literal: true

require './spec/spec_helper'

describe DataQualityChecker do
  let(:issue1) { load_issue('SP-1') }
  let(:issue2) { load_issue('SP-2') }
  let(:issue10) { load_issue('SP-10') }
  let(:subject) do
    subject = DataQualityChecker.new
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

    entry = DataQualityChecker::Entry.new started: nil, stopped: DateTime.parse('2021-12-25'), issue: issue1
    subject.scan_for_completed_issues_without_a_start_time entry: entry

    expect(entry.problems.size).to eq 1
    _problem_key, _detail, problem, _impact = *entry.problems.first
    expect(problem).to match 'finished but no start time can be found'
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

    entry = DataQualityChecker::Entry.new(
      started: nil, stopped: DateTime.parse('2021-09-06T04:34:26+00:00'), issue: issue10
    )
    subject.scan_for_status_change_after_done entry: entry

    expect(entry.problems.size).to eq 1
    _problem_key, _detail, problem, _impact = *entry.problems.first
    expect(problem).to match 'but status changes continued after that'
  end

  describe 'backwards movement' do
    it 'should detect backwards status' do
      subject.board_metadata = load_complete_sample_columns
      subject.possible_statuses = load_complete_sample_statuses
      subject.initialize_entries

      entry = DataQualityChecker::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-09-05', value_id: 3)
      issue1.changes << mock_change(
        field: 'status', value: 'Selected for Development', old_value: 'In Progress',
        time: '2021-09-06', value_id: 10_001
      )

      subject.scan_for_backwards_movement entry: entry

      expect(entry.problems.size).to eq 1
      _problem_key, _detail, _problem, impact = *entry.problems.first
      expect(impact).to match 'Backwards movement across statuses'
    end

    it 'should detect backwards status category' do
      subject.board_metadata = load_complete_sample_columns
      subject.possible_statuses = load_complete_sample_statuses
      subject.initialize_entries

      entry = DataQualityChecker::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      # Rank is there just to ensure that it gets skipped appropriately
      issue1.changes << mock_change(field: 'rank', value: 'more', time: '2021-09-04', value_id: 10_002)
      issue1.changes << mock_change(field: 'status', value: 'Done', time: '2021-09-05', value_id: 10_002)
      issue1.changes << mock_change(
        field: 'status', value: 'In Progress', old_value: 'Done',
        time: '2021-09-06', value_id: 3
      )

      subject.scan_for_backwards_movement entry: entry

      expect(entry.problems.size).to eq 1
      _problem_key, _detail, _problem, impact = *entry.problems.first
      expect(impact).to match 'Backwards movement across status categories'
    end

    it 'should detect statuses that just aren\'t on the board' do
      subject.board_metadata = load_complete_sample_columns
      subject.possible_statuses = load_complete_sample_statuses
      subject.initialize_entries

      entry = DataQualityChecker::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'Done', time: '2021-09-05', value_id: 999)

      subject.scan_for_backwards_movement entry: entry

      expect(entry.problems.size).to eq 1
      _problem_key, _detail, problem, _impact = *entry.problems.first
      expect(problem).to match "changed to a status that isn't visible"
    end

    it 'should detect skip past changes that are moving right' do
      subject.board_metadata = load_complete_sample_columns
      subject.possible_statuses = load_complete_sample_statuses
      subject.initialize_entries

      entry = DataQualityChecker::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(
        field: 'status', value: 'Selected for Development', old_value: 'In Progress',
        time: '2021-09-05', value_id: 10_001
      )
      issue1.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-09-06', value_id: 3)

      subject.scan_for_backwards_movement entry: entry

      expect(entry.problems).to be_empty
    end
  end

  describe 'scan_for_issues_not_created_in_the_right_status' do
    it 'should catch invalid starting status' do
      subject.board_metadata = load_complete_sample_columns
      subject.possible_statuses = load_complete_sample_statuses
      subject.initialize_entries

      entry = DataQualityChecker::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'Done', time: '2021-09-06', value_id: 10_002)

      subject.scan_for_issues_not_created_in_the_right_status entry: entry

      expect(entry.problems.size).to eq 1
      _problem_key, _detail, _problem, impact = *entry.problems.first
      expect(impact).to match 'Issues not created in the first column'
    end

    it 'should skip past valid status' do
      subject.board_metadata = load_complete_sample_columns
      subject.possible_statuses = load_complete_sample_statuses
      subject.initialize_entries

      entry = DataQualityChecker::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'ToDo', time: '2021-09-06', value_id: 10_000)

      subject.scan_for_issues_not_created_in_the_right_status entry: entry

      expect(entry.problems).to be_empty
    end
  end
end
