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
    subject = described_class.new([])
    subject.file_system = MockFileSystem.new
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

  it 'scans and finds no matches for anything' do
    report.issues = [empty_issue(created: '2024-01-01', board: board)]
    expect(report.run).to eq ''
    expect(report.file_system.log_messages).to be_empty
  end

  context 'templates' do
    # These aren't incredibly useful tests but there is value in ensuring that the templates do execute
    # without blowing up.

    it 'runs all the templates and verifies that they don\'t blow up' do
      expect(report.run).to match(/SP-1/)
      expect(report.file_system.log_messages).to be_empty
    end

    excluded_methods = %i[render_top_text render_problem_type]
    described_class.instance_methods.select { |m| m.to_s.start_with? 'render_' }.each do |method|
      next if excluded_methods.include? method

      it "can render #{method}" do
        report.__send__ method, []
        expect(report.file_system.log_messages).to be_empty
      end
    end
  end

  context 'scan_for_completed_issues_without_a_start_time' do
    it 'identifies items with completed but not started' do
      issue = empty_issue created: '2021-09-01', key: 'SP-1', board: board
      # report.all_boards = { board.id => board }
      add_mock_change(issue: issue, field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: Time.parse('2021-12-25'), issue: issue
      report.scan_for_completed_issues_without_a_start_time entry: entry

      expect(entry.problems).to eq [
        [
          :completed_but_not_started,
          "Status changes: #{report.format_status issue.changes.first, board: board}"
        ]
      ]
    end

    it 'skips items that are not done' do
      issue = empty_issue created: '2021-09-01', key: 'SP-1', board: board
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue
      report.scan_for_completed_issues_without_a_start_time entry: entry

      expect(entry.problems).to be_empty
    end
  end

  context 'scan_for_status_change_after_done' do
    it 'detects status changes after done' do
      # Issue 1 does have a resolution but no status after it.
      # Issue 2 has no resolutions at all
      # Issue 10 has a resolution with a status afterwards.

      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
      add_mock_change(
        issue: issue1, field: 'status', value: 'Done', value_id: 10_002, time: '2021-09-06T04:34:26+00:00'
      )

      report.issues << issue2

      issue10.changes.clear
      add_mock_change(issue: issue10, field: 'resolution', value: 'Done', time: '2021-09-06T04:34:26+00:00')
      done_change = add_mock_change(
        issue: issue10, field: 'status', value: 'Done', value_id: 10_002, time: '2021-09-06T04:34:26+00:00'
      )
      in_progress_change = add_mock_change(
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
          "Completed on 2021-09-06 with status #{report.format_status done_change, board: board}. " \
            "Changed to #{report.format_status in_progress_change, board: board} on 2021-09-07."
        ]
      ]
    end

    it 'skips when not stopped' do
      issue = empty_issue created: '2021-09-01', key: 'SP-1', board: board
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue
      report.scan_for_status_change_after_done entry: entry

      expect(entry.problems).to be_empty
    end
  end

  context 'backwards movement' do
    it 'detects backwards status' do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      change1 = add_mock_change(
        issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2021-09-05'
      )
      change2 = add_mock_change(
        issue: issue1, field: 'status',
        value: 'Selected for Development', value_id: 10_001,
        old_value: 'In Progress', old_value_id: 3,
        time: '2021-09-06'
      )

      report.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to eq [
        [
          :backwords_through_statuses,
          "Moved from #{report.format_status change1, board: board}" \
            " to #{report.format_status change2, board: board}" \
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

      in_progress_status = entry.issue.board.possible_statuses.find_by_id 3
      done_status = entry.issue.board.possible_statuses.find_by_id 10_002

      expect(entry.problems).to eq [
        [
          :backwards_through_status_categories,
          "Moved from #{report.format_status done_status, board: board} " \
            "to #{report.format_status in_progress_status, board: board} on 2021-09-06, " \
            "crossing from category #{report.format_status done_status, board: board, is_category: true}" \
            " to #{report.format_status in_progress_status, board: board, is_category: true}."

        ]
      ]
    end

    it "detects statuses that just aren't on the board" do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      fake_backlog_status = add_mock_change(
        issue: issue1, field: 'status', value: 'FakeBacklog', time: '2021-09-05', value_id: 10_012
      )
      report.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to eq [
        [
          :status_not_on_board,
          "Status #{report.format_status fake_backlog_status, board: board} is not on the board"
        ]
      ]
    end

    it "detects statuses that just don't exist anymore" do
      report.all_boards = { 1 => board }
      report.initialize_entries

      entry = DataQualityReport::Entry.new started: nil, stopped: nil, issue: issue1

      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'Foo', value_id: 100, time: '2021-09-05')
      report.scan_for_backwards_movement entry: entry, backlog_statuses: []

      expect(entry.problems).to eq [
        [
          :status_not_on_board,
          "Status #{report.format_status issue1.changes.first, board: board} cannot be found at all. Was it deleted?"
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
      done_change = add_mock_change(issue: issue1, field: 'status', value: 'Done', time: '2021-09-06', value_id: 10_002)

      report.scan_for_issues_not_created_in_a_backlog_status(
        entry: entry, backlog_statuses: board.backlog_statuses
      )

      backlog_status = board.possible_statuses.find { |s| s.name == 'Backlog' }
      expect(entry.problems).to eq [
        [
          :created_in_wrong_status,
          "Created in #{report.format_status done_change, board: entry.issue.board}, " \
            'which is not one of the backlog statuses for this board: ' \
            "#{report.format_status backlog_status, board: entry.issue.board}"
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
          report.subtask_label(subtask)
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
          "#{report.subtask_label(subtask)} (Not even started)"
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
          "#{report.subtask_label(subtask)} (Closed 9 days later)"
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
          "#{report.subtask_label(subtask)} (Still not done)"
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
      report.discarded_changes_data << {
        issue: issue1,
        original_start_time: to_time('2022-01-01'),
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
      report.discarded_changes_data << {
        issue: issue1,
        original_start_time: to_time('2022-01-01'),
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
      report.discarded_changes_data << {
        issue: issue1,
        original_start_time: to_time('2022-01-01T01:00:00'),
        cutoff_time: to_time('2022-01-01T02:00:00')
      }
      entry = DataQualityReport::Entry.new(
        started: to_time('2022-01-01T03:00:00'), stopped: nil, issue: issue1
      )
      report.scan_for_discarded_data entry: entry
      expect(entry.problems).to be_empty
    end

    it 'works end-to-end' do
      # There is a complex set of conditions that are required to get the 'moved back to backlog'
      # functionality to work. This verifies that all the pieces talk to each other at the right times
      # and that the right issues are identified. We've already had one case where this just stopped
      # working and we didn't realize it.
      exporter = Exporter.new file_system: MockFileSystem.new
      target_path = 'spec/complete_sample/'

      sp1_json = empty_issue(created: '2021-09-15', key: 'SP-1').raw
      exporter.file_system.when_loading file: "#{target_path}sample_statuses.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{target_path}sample_meta.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{target_path}sample_board_1_configuration.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{target_path}sample_issues/SP-1.json", json: sp1_json
      exporter.file_system.when_loading file: "#{target_path}sample_issues/SP-2.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{target_path}sample_issues/SP-5.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{target_path}sample_issues/SP-7.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{target_path}sample_issues/SP-8.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{target_path}sample_issues/SP-11.json", json: :not_mocked
      exporter.file_system.when_foreach root: target_path, result: :not_mocked

      project_config = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: lambda do |_|
          file_prefix 'sample'
          board id: 1 do
            cycletime do
              start_at first_time_in_status_category('In Progress')
              stop_at still_in_status_category('Done')
            end
          end

          # Force SP-1 back to the backlog
          issues.find { |issue| issue.key == 'SP-1' }.tap do |issue|
            add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2021-09-16')
            add_mock_change(issue: issue, field: 'status', value: 'Backlog', value_id: 10_000, time: '2021-09-17')
          end

          discard_changes_before status_becomes: :backlog

          file do
            file_suffix '.html'
            html_report do # Don't need to specify charts if all we need is the quality report
              cycletime_scatterplot
            end
          end
        end
      )
      project_config.evaluate_next_level
      project_config.run

      file_config = project_config.file_configs.first
      html_report = file_config.children.first
      data_quality_report = html_report.charts.find { |c| c.is_a? described_class }

      expect(exporter.file_system.log_messages).to match_strings [
        # 'Warning: No charts were specified for the report. This is almost certainly a mistake.',
        /^Loaded CSS/
      ]

      actual = data_quality_report.problems_for(:discarded_changes).collect do |issue, message, key|
        [issue.key, message, key]
      end
      expect(actual).to eq [
        [
          'SP-1',
          'Started: 2021-09-16, Discarded: 2021-09-17, Ignored: 2 days',
          :discarded_changes
        ]
      ]
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

  context 'scan_for_items_blocked_on_closed_tickets' do
    it 'does the scan' do
      entry1 = DataQualityReport::Entry.new(started: nil, stopped: nil, issue: issue1)
      link = IssueLink.new origin: issue1, raw: {
        # 'id' => '10001',
        # 'self' => 'https://improvingflow.atlassian.net/rest/api/2/issueLink/10001',
        'type' => {
          # 'id' => '10006',
          'name' => 'Blocked',
          'inward' => 'is blocked by',
          'outward' => 'blocks',
          # 'self' => 'https://improvingflow.atlassian.net/rest/api/2/issueLinkType/10006'
        },
        'inwardIssue' => {
          'id' => '10019',
          'key' => issue2.key,
          # 'self' => 'https://improvingflow.atlassian.net/rest/api/2/issue/10019',
          'fields' => {
            # 'summary' => 'Report of all events',
            'status' => {
              'self' => 'https://improvingflow.atlassian.net/rest/api/2/status/10002',
              'description' => '',
              'iconUrl' => 'https://improvingflow.atlassian.net/',
              'name' => 'Done',
              'id' => '10002',
              'statusCategory' => {
                'self' => 'https://improvingflow.atlassian.net/rest/api/2/statuscategory/3',
                'id' => 3,
                'key' => 'done',
                'colorName' => 'green',
                'name' => 'Done'
              }
            },
            'priority' => {
              'self' => 'https://improvingflow.atlassian.net/rest/api/2/priority/3',
              'iconUrl' => 'https://improvingflow.atlassian.net/images/icons/priorities/medium.svg',
              'name' => 'Medium',
              'id' => '3'
            },
            'issuetype' => {
              'self' => 'https://improvingflow.atlassian.net/rest/api/2/issuetype/10001',
              'id' => '10001',
              'description' => 'Functionality or a feature expressed as a user goal.',
              'iconUrl' => 'https://improvingflow.atlassian.net/rest/api/2/universal_avatar/view/type/issuetype/avatar/10315?size=medium',
              'name' => 'Story',
              'subtask' => false,
              'avatarId' => 10_315,
              'hierarchyLevel' => 0
            }
          }
        }
      }
      link.other_issue = issue2
      issue1.issue_links << link
      issue1.board.cycletime = mock_cycletime_config stub_values: [
        [issue2, nil, to_time('2024-01-01')]
      ]

      report.scan_for_items_blocked_on_closed_tickets entry: entry1
      expect(entry1.problems).to eq [
        [:items_blocked_on_closed_tickets, "SP-1 thinks it's blocked by SP-2, except SP-2 is closed."]
      ]
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
