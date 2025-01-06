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

  let(:report) do
    subject = described_class.new({})
    subject.issues = [issue10, issue1]
    subject.time_range = to_time('2021-06-01')..to_time('2021-10-01')
    subject
  end

  it 'creates entries' do
    report.initialize_entries

    expect(report.testable_entries).to eq [
      ['2021-06-18 18:43:34 +0000', '', issue1],
      ['2021-08-29 18:06:28 +0000', '2021-09-06 04:34:26 +0000', issue10]
    ]

    expect(report.entries_with_problems).to be_empty
  end

  it 'ignores entries that finished before the range' do
    board.cycletime = mock_cycletime_config stub_values: [
      [issue1, nil, to_time('2021-05-01')],
      [issue10, to_time('2021-08-29'), to_time('2021-09-06')]
    ]
    report.initialize_entries

    expect(report.testable_entries).to eq [
      ['2021-08-29 00:00:00 +0000', '2021-09-06 00:00:00 +0000', issue10]
    ]
  end

  it 'ignores entries that started after the range' do
    board.cycletime = mock_cycletime_config stub_values: [
      [issue1, to_time('2022-01-01'), nil],
      [issue10, to_time('2021-08-29'), to_time('2021-09-06')]
    ]
    report.initialize_entries

    expect(report.testable_entries).to eq [
      ['2021-08-29 00:00:00 +0000', '2021-09-06 00:00:00 +0000', issue10]
    ]
  end

  it 'identifies items with completed but not started' do
    issue1.changes.clear
    add_mock_change(issue: issue1, field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
    report.initialize_entries

    entry = DataQualityReport::Entry.new started: nil, stopped: Time.parse('2021-12-25'), issue: issue1
    report.scan_for_completed_issues_without_a_start_time entry: entry

    expect(entry.problems).to eq [
      [
        :completed_but_not_started,
        'Status changes: ' # TODO: Clearly this description is incomplete
      ]
    ]
  end

  it 'detects status changes after done' do
    # Issue 1 does have a resolution but no status after it.
    # Issue 2 has no resolutions at all
    # Issue 10 has a resolution with a status afterwards.

    issue1.changes.clear
    add_mock_change(issue: issue1, field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
    add_mock_change(issue: issue1, field: 'status', value: 'Done', value_id: 10_002, time: '2021-09-06T04:34:26+00:00')

    report.issues << issue2

    issue10.changes.clear
    add_mock_change(issue: issue10, field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
    add_mock_change(issue: issue10, field: 'status', value: 'Done', value_id: 10_002, time: '2021-09-06T04:34:26+00:00')
    add_mock_change(
      issue: issue10, field: 'status', value: 'In Progress', value_id: 3, time: '2021-09-07T04:34:26+00:00'
    )
    report.initialize_entries

    entry = DataQualityReport::Entry.new(
      started: nil, stopped: Time.parse('2021-09-06T04:34:26+00:00'), issue: issue10
    )
    report.scan_for_status_change_after_done entry: entry

    expect(entry.problems).to eq [
      [
        :status_changes_after_done,
        "Completed on 2021-09-06 with status #{report.format_status 'Done', board: board}. " \
          "Changed to #{report.format_status 'In Progress', board: board} on 2021-09-07."
      ]
    ]
  end

  context 'backwards movement' do
    it 'detects backwards status' do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', time: '2021-09-05', value_id: 3)
      add_mock_change(
        issue: issue1,
        field: 'status', value: 'Selected for Development', old_value: 'In Progress',
        time: '2021-09-06', value_id: 10_001, old_value_id: 3
      )

      report.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to eq [
        [
          :backwords_through_statuses,
          "Moved from #{report.format_status 'In Progress', board: board}" \
            " to #{report.format_status 'Selected for Development', board: board}" \
            ' on 2021-09-06'
        ]
      ]
    end

    it 'detects backwards status category' do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      # Rank is there just to ensure that it gets skipped appropriately
      add_mock_change(issue: issue1, field: 'rank', value: 'more', time: '2021-09-04', value_id: 10_002)
      add_mock_change(issue: issue1, field: 'status', value: 'Done', time: '2021-09-05', value_id: 10_002)
      add_mock_change(
        issue: issue1, field: 'status',
        value: 'In Progress', value_id: 3,
        old_value: 'Done', old_value_id: 10_002,
        time: '2021-09-06'
      )

      report.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to eq [
        [
          :backwards_through_status_categories,
          "Moved from #{report.format_status 'Done', board: board} " \
            "to #{report.format_status 'In Progress', board: board} on 2021-09-06, " \
            "crossing from category #{report.format_status 'Done', board: board, is_category: true}" \
            " to #{report.format_status 'In Progress', board: board, is_category: true}."

        ]
      ]
    end

    it "detects statuses that just aren't on the board" do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'FakeBacklog', time: '2021-09-05', value_id: 10_012)
      report.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to eq [
        [
          :status_not_on_board,
          "Status #{report.format_status 'FakeBacklog', board: board} is not on the board"
        ]
      ]
    end

    it "detects statuses that just don't exist anymore" do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'Foo', time: '2021-09-05', value_id: 100)
      report.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to eq [
        [
          :status_not_on_board,
          "Status #{report.format_status 'Foo', board: board} cannot be found at all. Was it deleted?"
        ]
      ]
    end

    it 'detects skip past changes that are moving right' do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      add_mock_change(
        issue: issue1,
        field: 'status', value: 'Selected for Development', old_value: 'In Progress',
        time: '2021-09-05', value_id: 10_001, old_value_id: 3
      )
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', time: '2021-09-06', value_id: 3)

      report.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to be_empty
    end
  end

  context 'scan_for_issues_not_created_in_the_right_status' do
    it 'catches invalid starting status' do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'Done', time: '2021-09-06', value_id: 10_002)

      board.backlog_statuses << Status.new(
        name: 'foo', id: 10_000, category_name: 'bar', category_id: 2, category_key: 'new'
      )
      report.scan_for_issues_not_created_in_a_backlog_status(
        entry: entry, backlog_statuses: board.backlog_statuses
      )

      expect(entry.problems).to eq [
        [
          :created_in_wrong_status,
          "Created in #{report.format_status 'Done', board: entry.issue.board}, " \
            'which is not one of the backlog statuses for this board: ' \
            "#{report.format_status 'Backlog', board: entry.issue.board}, " \
            "#{report.format_status 'foo', board: entry.issue.board}"
        ]
      ]
    end

    it 'is ok when issue created in a correct backlog status' do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'Backlog', time: '2021-09-06', value_id: 10_000)
      board.backlog_statuses << Status.new(
        name: 'foo', id: 10_000, category_name: 'bar', category_id: 2, category_key: 'new'
      )
      report.scan_for_issues_not_created_in_a_backlog_status(
        entry: entry, backlog_statuses: board.backlog_statuses
      )

      expect(entry.problems).to be_empty
    end
  end

  context 'scan_for_stopped_before_started' do
    it 'accepts correct data' do
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-02'), stopped: to_time('2022-01-03'), issue: issue1
      )
      report.scan_for_stopped_before_started entry: entry
      expect(entry.problems).to eq []
    end

    it 'identifies incorrect data' do
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-04'), stopped: to_time('2022-01-03'), issue: issue1
      )
      report.scan_for_stopped_before_started entry: entry
      expect(entry.problems).to eq [
        [
          :stopped_before_started,
          "The stopped time '2022-01-03 00:00:00 +0000' is before the started time '2022-01-04 00:00:00 +0000'"
        ]
      ]
    end
  end

  context 'scan_for_issues_not_started_with_subtasks_that_have' do
    let(:subtask) do
      subtask = load_issue('SP-2', board: board)
      subtask.raw['fields']['issuetype']['name'] = 'Sub-task'
      subtask.changes.clear
      subtask
    end

    it 'ignores subtasks that also have not started' do
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: to_time('2022-01-03'), issue: issue1
      )

      issue1.subtasks << subtask

      report.scan_for_issues_not_started_with_subtasks_that_have entry: entry
      expect(entry.problems).to eq []
    end

    it 'flags subtasks that are started when main issue is not' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, to_time('2022-01-03'), nil]
      ]
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: nil, issue: issue1
      )
      issue1.subtasks << subtask

      report.scan_for_issues_not_started_with_subtasks_that_have entry: entry

      expect(entry.problems).to eq [
        [
          :issue_not_started_but_subtasks_have,
          "<img src='https://improvingflow.atlassian.net/secure/viewavatar?size=medium&avatarId=10315&" \
          "avatarType=issuetype' /> <a href='https://improvingflow.atlassian.net/browse/SP-2' class='issue_key'>" \
          'SP-2</a> "Update existing event"'
        ]
      ]
    end

    it 'catches subtasks that are not started when main issue is closed' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, nil, nil]
      ]
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: to_time('2024-01-01'), issue: issue1
      )
      issue1.subtasks << subtask

      report.scan_for_incomplete_subtasks_when_issue_done entry: entry

      expect(entry.problems).to eq [
        [
          :incomplete_subtasks_when_issue_done,
          "<img src='https://improvingflow.atlassian.net/secure/viewavatar?size=medium&avatarId=10315&" \
          "avatarType=issuetype' /> <a href='https://improvingflow.atlassian.net/browse/SP-2' class='issue_key'>" \
          'SP-2</a> "Update existing event" (Not even started)'
        ]
      ]
    end

    it 'catches subtasks that are closed after the main issue' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, nil, to_time('2024-01-10')]
      ]
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: to_time('2024-01-01'), issue: issue1
      )
      issue1.subtasks << subtask

      report.scan_for_incomplete_subtasks_when_issue_done entry: entry

      expect(entry.problems).to eq [
        [
          :incomplete_subtasks_when_issue_done,
          "<img src='https://improvingflow.atlassian.net/secure/viewavatar?size=medium&avatarId=10315&" \
          "avatarType=issuetype' /> <a href='https://improvingflow.atlassian.net/browse/SP-2' class='issue_key'>" \
          'SP-2</a> "Update existing event" (Closed 9 days later)'
        ]
      ]
    end

    it 'catches subtasks that still are not closed after the main issue was closed' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, to_time('2024-01-02'), nil]
      ]
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: to_time('2024-01-01'), issue: issue1
      )
      issue1.subtasks << subtask

      report.scan_for_incomplete_subtasks_when_issue_done entry: entry

      expect(entry.problems).to eq [
        [
          :incomplete_subtasks_when_issue_done,
          "<img src='https://improvingflow.atlassian.net/secure/viewavatar?size=medium&avatarId=10315&" \
          "avatarType=issuetype' /> <a href='https://improvingflow.atlassian.net/browse/SP-2' class='issue_key'>" \
          'SP-2</a> "Update existing event" (Still not done)'
        ]
      ]
    end

    it 'ignores subtasks that did close before the main issue was closed' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, nil, to_time('2024-01-01')]
      ]
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: to_time('2024-01-02'), issue: issue1
      )
      issue1.subtasks << subtask

      report.scan_for_incomplete_subtasks_when_issue_done entry: entry

      expect(entry.problems).to be_empty
    end

    it 'ignores issues that are not closed' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, nil, to_time('2024-01-01')]
      ]
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: nil, issue: issue1
      )
      issue1.subtasks << subtask

      report.scan_for_incomplete_subtasks_when_issue_done entry: entry

      expect(entry.problems).to be_empty
    end

    it 'ignores subtasks that are started when the main issue is also started' do
      board.cycletime = mock_cycletime_config stub_values: [
        [subtask, to_time('2022-01-03'), nil]
      ]
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-04'), stopped: nil, issue: issue1
      )

      issue1.subtasks << subtask

      report.scan_for_issues_not_started_with_subtasks_that_have entry: entry
      expect(entry.problems).to be_empty
    end
  end

  context 'label_issues' do
    it 'handles singular' do
      expect(report.label_issues(1)).to eq '1 item'
    end

    it 'handles plural' do
      expect(report.label_issues(2)).to eq '2 items'
    end
  end

  context 'scan_for_discarded_data' do
    it 'handles nothing discarded' do
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-02'), stopped: to_time('2022-01-03'), issue: issue1
      )
      report.scan_for_discarded_data entry: entry
      expect(entry.problems).to eq []
    end

    it 'handles discarded and restarted' do
      report.date_range = to_date('2022-01-01')..to_date('2022-01-20')
      report.original_issue_times[issue1] = {
        started_time: to_time('2022-01-01'),
        cutoff_time: to_time('2022-01-03')
      }
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-05'), stopped: to_time('2022-02-03'), issue: issue1
      )
      report.scan_for_discarded_data entry: entry
      expect(entry.problems).to eq [
        [:discarded_changes, 'Started: 2022-01-01, Discarded: 2022-01-03, Ignored: 3 days']
      ]
    end

    it 'handles discarded with no restart' do
      report.date_range = to_date('2022-01-01')..to_date('2022-01-20')
      report.original_issue_times[issue1] = {
        started_time: to_time('2022-01-01'),
        cutoff_time: to_time('2022-01-03')
      }
      entry = DataQualityReport::Entry.new(
        started: nil, stopped: nil, issue: issue1
      )
      report.scan_for_discarded_data entry: entry
      expect(entry.problems).to eq [
        [:discarded_changes, 'Started: 2022-01-01, Discarded: 2022-01-03, Ignored: 3 days']
      ]
    end

    it 'handles discarded that results in no days ignored' do
      report.date_range = to_date('2022-01-01')..to_date('2022-01-20')
      report.original_issue_times[issue1] = {
        started_time: to_time('2022-01-01T01:00:00'),
        cutoff_time: to_time('2022-01-01T02:00:00')
      }
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-01T03:00:00'), stopped: nil, issue: issue1
      )
      report.scan_for_discarded_data entry: entry
      expect(entry.problems).to be_empty
    end
  end

  context 'scan_for_issues_on_multiple_boards' do
    it 'does not report errors when no duplicates' do
      entry1 = DataQualityReport::Entry.new(started: nil, stopped: nil, issue: issue1)
      entry2 = DataQualityReport::Entry.new(started: nil, stopped: nil, issue: issue2)
      report.scan_for_issues_on_multiple_boards entries: [entry1, entry2]

      expect(entry1.problems).to be_empty
      expect(entry2.problems).to be_empty
    end

    it 'does report errors when no duplicates' do
      board2 = Board.new raw: {
        'name' => 'bar',
        'type' => 'kanban',
        'columnConfig' => {
          'columns' => [
            {
              'name' => 'Backlog',
              'statuses' => []
            }
          ]
        }
      }, possible_statuses: StatusCollection.new
      issue1a = load_issue 'SP-1', board: board2
      entry1 = DataQualityReport::Entry.new(started: nil, stopped: nil, issue: issue1)
      entry2 = DataQualityReport::Entry.new(started: nil, stopped: nil, issue: issue1a)
      report.scan_for_issues_on_multiple_boards entries: [entry1, entry2]

      expect(entry1.problems).to eq [
        [:issue_on_multiple_boards, 'Found on boards: "SP board", "bar"']
      ]
      expect(entry2.problems).to be_empty
    end
  end

  context 'time_as_english' do
    it 'handles seconds' do
      expect(report.time_as_english to_time('2024-01-01'), to_time('2024-01-01T00:00:07')).to eq('7 seconds')
    end

    it 'handles minutes' do
      expect(report.time_as_english to_time('2024-01-01'), to_time('2024-01-01T00:08:00')).to eq('8 minutes')
    end

    it 'handles hours' do
      expect(report.time_as_english to_time('2024-01-01'), to_time('2024-01-01T11:00:00')).to eq('11 hours')
    end
  end
end
