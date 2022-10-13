# frozen_string_literal: true

require './spec/spec_helper'

describe DataQualityReport do
  let(:board) do
    load_complete_sample_board.tap do |board|
      today = Date.parse('2021-12-17')
      block = lambda do |_|
      start_at first_status_change_after_created
      stop_at last_resolution
    end

      board.cycletime = CycleTimeConfig.new parent_config: nil, label: 'default', block: block, today: today
    end
  end
  let(:issue1) { load_issue('SP-1', board: board) }
  let(:issue2) { load_issue('SP-2', board: board) }
  let(:issue10) { load_issue('SP-10', board: board) }

  let(:subject) do
    subject = DataQualityReport.new({})
    subject.issues = [issue10, issue1]
    subject.possible_statuses = load_complete_sample_statuses

    subject
  end

  it 'should create entries' do
    subject.initialize_entries

    expect(subject.testable_entries).to eq [
      ['2021-06-18 18:43:34 +0000', '', issue1],
      ['2021-08-29 18:06:28 +0000', '2021-09-06 04:34:26 +0000', issue10]
    ]

    expect(subject.entries_with_problems).to be_empty
  end

  it 'should identify items with completed but not started' do
    issue1.changes.clear
    issue1.changes << mock_change(field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
    subject.initialize_entries

    entry = DataQualityReport::Entry.new started: nil, stopped: Time.parse('2021-12-25'), issue: issue1
    subject.scan_for_completed_issues_without_a_start_time entry: entry

    expect(entry.problems.size).to eq 1
    problem_key, _detail = *entry.problems.first
    expect(problem_key).to eq :completed_but_not_started
  end

  it 'should detect status changes after done' do
    # Issue 1 does have a resolution but no status after it.
    # Issue 2 has no resolutions at all
    # Issue 10 has a resolution with a status afterwards.

    issue1.changes.clear
    issue1.changes << mock_change(field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
    issue1.changes << mock_change(field: 'status', value: 'Done', time: '2021-09-06T04:34:26+00:00')

    subject.issues << issue2

    issue10.changes.clear
    issue10.changes << mock_change(field: 'resolution', value: 'Done',    time: '2021-09-06T04:34:26+00:00')
    issue10.changes << mock_change(field: 'status', value: 'Done',        time: '2021-09-06T04:34:26+00:00')
    issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-09-07T04:34:26+00:00')
    subject.initialize_entries

    entry = DataQualityReport::Entry.new(
      started: nil, stopped: Time.parse('2021-09-06T04:34:26+00:00'), issue: issue10
    )
    subject.scan_for_status_change_after_done entry: entry

    expect(entry.problems.size).to eq 1
    problem_key, _detail = *entry.problems.first
    expect(problem_key).to match :status_changes_after_done
  end

  context 'backwards movement' do
    it 'should detect backwards status' do
      subject.all_boards = { 1 => board }
      subject.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-09-05', value_id: 3)
      issue1.changes << mock_change(
        field: 'status', value: 'Selected for Development', old_value: 'In Progress',
        time: '2021-09-06', value_id: 10_001
      )

      subject.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems.size).to eq 1
      problem_key, _detail = *entry.problems.first
      expect(problem_key).to match :backwords_through_statuses
    end

    it 'should detect backwards status category' do
      subject.all_boards = { 1 => board }
      subject.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      # Rank is there just to ensure that it gets skipped appropriately
      issue1.changes << mock_change(field: 'rank', value: 'more', time: '2021-09-04', value_id: 10_002)
      issue1.changes << mock_change(field: 'status', value: 'Done', time: '2021-09-05', value_id: 10_002)
      issue1.changes << mock_change(
        field: 'status', value: 'In Progress', old_value: 'Done',
        time: '2021-09-06', value_id: 3
      )

      subject.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems.size).to eq 1
      problem_key, _detail = *entry.problems.first
      expect(problem_key).to eq :backwards_through_status_categories
    end

    it 'should detect statuses that just aren\'t on the board' do
      subject.all_boards = { 1 => board }
      subject.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'Done', time: '2021-09-05', value_id: 999)
      subject.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems.size).to eq 1
      problem_key, _detail = *entry.problems.first
      expect(problem_key).to eq :status_not_on_board
    end

    it 'should detect skip past changes that are moving right' do
      subject.all_boards = { 1 => board }
      subject.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(
        field: 'status', value: 'Selected for Development', old_value: 'In Progress',
        time: '2021-09-05', value_id: 10_001
      )
      issue1.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-09-06', value_id: 3)

      subject.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to be_empty
    end
  end

  context 'scan_for_issues_not_created_in_the_right_status' do
    it 'should catch invalid starting status' do
      subject.all_boards = { 1 => board }
      subject.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'Done', time: '2021-09-06', value_id: 10_002)

      subject.scan_for_issues_not_created_in_the_right_status entry: entry

      expect(entry.problems.size).to eq 1
      problem_key, _detail = *entry.problems.first
      expect(problem_key).to eq :created_in_wrong_status
    end

    it 'should skip past valid status' do
      subject.all_boards = { 1 => board }
      subject.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'ToDo', time: '2021-09-06', value_id: 10_000)

      subject.scan_for_issues_not_created_in_the_right_status entry: entry

      expect(entry.problems).to be_empty
    end
  end

  context 'scan_for_stopped_before_started' do
    it 'should accept correct data' do
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-02'), stopped: to_time('2022-01-03'), issue: issue1
      )
      subject.scan_for_stopped_before_started entry: entry
      expect(entry.problems).to eq []
    end

    it 'should identify incorrect data' do
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-04'), stopped: to_time('2022-01-03'), issue: issue1
      )
      subject.scan_for_stopped_before_started entry: entry
      expect(entry.problems).to eq [
        [
          :stopped_before_started,
          "The stopped time '2022-01-03 00:00:00 +0000' is before the started time '2022-01-04 00:00:00 +0000'",
          nil, nil
        ]
      ]
    end
  end

  context 'format_status' do
    it 'should make text red when status not found' do
      expect(subject.format_status 'Digging').to eq "<span style='color: red'>Digging</span>"
    end

    it 'should handle todo statuses' do
      expect(subject.format_status 'Backlog').to eq "<span style='color: gray'>Backlog</span>"
    end

    it 'should handle in progress statuses' do
      expect(subject.format_status 'Review').to eq "<span style='color: blue'>Review</span>"
    end

    it 'should handle done statuses' do
      expect(subject.format_status 'Done').to eq "<span style='color: green'>Done</span>"
    end

    it 'should handle unknown statuses' do
      expect(subject.format_status 'unknown').to eq "<span style='color: red'>unknown</span>"
    end
  end

  context 'scan_for_issues_not_started_with_subtasks_that_have' do
    let(:subtask) do
      subtask = load_issue('SP-2', board: board)
      subtask.raw['fields']['issuetype']['name'] = 'Sub-task'
      subtask.changes.clear
      subtask
    end

    it 'should ignore subtasks that also have not started' do
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: to_time('2022-01-03'), issue: issue1
      )

      issue1.subtasks << subtask

      subject.scan_for_issues_not_started_with_subtasks_that_have entry: entry
      expect(entry.problems).to eq []
    end

    it 'should flag subtasks that are started when main issue is not' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, to_time('2022-01-03'), nil]
      ]
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: nil, issue: issue1
      )
      issue1.subtasks << subtask

      subject.scan_for_issues_not_started_with_subtasks_that_have entry: entry

      expect(entry.problems).to eq [
        [
          :issue_not_started_but_subtasks_have,
          "Started subtask: <a href='https://improvingflow.atlassian.net/browse/SP-2' class='issue_key'>SP-2</a>" \
            " (<span style='color: blue'>Selected for Development</span>) \"Update existing event\"",
          nil,
          nil
        ]
      ]
    end

    it 'should ignore subtasks that are started when the main issue is also started' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, to_time('2022-01-03'), nil]
      ]
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-04'), stopped: nil, issue: issue1
      )

      issue1.subtasks << subtask

      subject.scan_for_issues_not_started_with_subtasks_that_have entry: entry
      expect(entry.problems).to be_empty
    end
  end

  context 'label_issues' do
    it 'should handle singular' do
      expect(subject.label_issues(1)).to eq '1 item'
    end

    it 'should handle plural' do
      expect(subject.label_issues(2)).to eq '2 items'
    end
  end

  context 'scan_for_discarded_data' do
    it 'should handle nothing discarded' do
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-02'), stopped: to_time('2022-01-03'), issue: issue1
      )
      subject.scan_for_discarded_data entry: entry
      expect(entry.problems).to eq []
    end

    it 'should handle discarded and restarted' do
      subject.date_range = to_date('2022-01-01')..to_date('2022-01-20')
      subject.original_issue_times[issue1] = {
        started_time: to_time('2022-01-01'),
        cutoff_time: to_time('2022-01-03')
      }
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-05'), stopped: to_time('2022-02-03'), issue: issue1
      )
      subject.scan_for_discarded_data entry: entry
      expect(entry.problems).to eq [
        [:discarded_changes, 'Started: 2022-01-01, Discarded: 2022-01-03, Ignored: 3 days', nil, nil]
      ]
    end

    it 'should handle discarded with no restart' do
      subject.date_range = to_date('2022-01-01')..to_date('2022-01-20')
      subject.original_issue_times[issue1] = {
        started_time: to_time('2022-01-01'),
        cutoff_time: to_time('2022-01-03')
      }
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: nil, issue: issue1
      )
      subject.scan_for_discarded_data entry: entry
      expect(entry.problems).to eq [
        [:discarded_changes, 'Started: 2022-01-01, Discarded: 2022-01-03, Ignored: 3 days', nil, nil]
      ]
    end

    it 'should handle discarded with no restart' do
      subject.date_range = to_date('2022-01-01')..to_date('2022-01-20')
      subject.original_issue_times[issue1] = {
        started_time: to_time('2022-01-01'),
        cutoff_time: to_time('2022-01-03')
      }
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: nil, issue: issue1
      )
      subject.scan_for_discarded_data entry: entry
      expect(entry.problems).to eq [
        [:discarded_changes, 'Started: 2022-01-01, Discarded: 2022-01-03, Ignored: 3 days', nil, nil]
      ]
    end

    it 'should handle discarded that results in no days ignored' do
      subject.date_range = to_date('2022-01-01')..to_date('2022-01-20')
      subject.original_issue_times[issue1] = {
        started_time: to_time('2022-01-01T01:00:00'),
        cutoff_time: to_time('2022-01-01T02:00:00')
      }
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-01T03:00:00'), stopped: nil, issue: issue1
      )
      subject.scan_for_discarded_data entry: entry
      expect(entry.problems).to be_empty
    end
  end
end
