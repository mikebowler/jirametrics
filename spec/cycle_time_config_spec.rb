# frozen_string_literal: true

require './spec/spec_helper'

describe CycleTimeConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:target_path) { 'spec/testdata/' }
  let(:project_config) do
    exporter.file_system.when_loading file: 'spec/testdata/sample_statuses.json', json: :not_mocked
    exporter.file_system.when_loading file: 'spec/testdata/sample_board_1_configuration.json', json: :not_mocked

    ProjectConfig.new(exporter: exporter, target_path: target_path, jira_config: nil, block: nil)
  end
  let(:issue) { load_issue 'SP-1' }

  describe 'deprecated methods' do
    it 'deprecates methods that return a time' do
      config = described_class.new(
        possible_statuses: nil, label: 'foo', file_system: exporter.file_system, settings: load_settings,
        block: lambda do |_|
          start_at created
          stop_at created
        end
      )
      config.started_stopped_changes issue
      expect(exporter.file_system.log_messages).to match_strings [
        /Deprecated\(2024-12-16\): This method should now return a ChangeItem not a Time/,
        /Deprecated\(2024-12-16\): This method should now return a ChangeItem not a Time/
      ]
    end
  end

  describe '#started_stopped_changes' do
    let(:settings) { load_settings }
    let(:cycletime) do
      described_class.new(
        possible_statuses: nil,
        label: 'foo',
        file_system: exporter.file_system,
        settings: settings,
        block: lambda do |_|
          start_at first_time_in_status('In Progress')
          stop_at first_time_in_status('Done')
        end
      )
    end

    it 'returns the same value twice in a row when cached, but issue changes' do
      settings['cache_cycletime_calculations'] = true
      issue = empty_issue created: '2025-01-01', board: sample_board
      issue.changes.clear
      change1 = add_mock_change(
        issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2025-01-03'
      )
      change2 = add_mock_change(
        issue: issue, field: 'status', value: 'Done', value_id: 10_002, time: '2025-01-05'
      )
      expect(cycletime.started_stopped_changes issue).to eq([change1, change2])

      issue.changes.delete change1

      # If this wasn't cached then started would now be nil, but we are cached
      expect(cycletime.started_stopped_changes issue).to eq([change1, change2])
    end

    it 'returns different values when not cached, and issue changes' do
      settings['cache_cycletime_calculations'] = false
      issue = empty_issue created: '2025-01-01', board: sample_board
      issue.changes.clear
      change1 = add_mock_change(
        issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2025-01-03'
      )
      change2 = add_mock_change(
        issue: issue, field: 'status', value: 'Done', value_id: 10_002, time: '2025-01-05'
      )
      expect(cycletime.started_stopped_changes issue).to eq([change1, change2])

      issue.changes.delete change1

      expect(cycletime.started_stopped_changes issue).to eq([nil, change2])
      expect(cycletime.file_system.log_messages).to eq [
        'Error: Calculation mismatch; this could break caching. Issue("SP-1") ' \
          'new=[' \
            'nil, ' \
            'ChangeItem(field: "status", value: "Done":10002, time: "2025-01-05 00:00:00 +0000")' \
          '], ' \
          'previous=[' \
            'ChangeItem(field: "status", value: "In Progress":3, time: "2025-01-03 00:00:00 +0000"), ' \
            'ChangeItem(field: "status", value: "Done":10002, time: "2025-01-05 00:00:00 +0000")' \
          ']'
      ]
    end

    it 'returns same values when not cached, and nothing changes' do
      settings['cache_cycletime_calculations'] = false
      issue = empty_issue created: '2025-01-01', board: sample_board
      issue.changes.clear
      change1 = add_mock_change(
        issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2025-01-03'
      )
      change2 = add_mock_change(
        issue: issue, field: 'status', value: 'Done', value_id: 10_002, time: '2025-01-05'
      )

      # We really call it twice in a row - this isn't a mistake
      expect(cycletime.started_stopped_changes issue).to eq([change1, change2])
      expect(cycletime.started_stopped_changes issue).to eq([change1, change2])
      expect(cycletime.file_system.log_messages).to be_empty
    end

    # Build a config whose start/stop blocks return exactly what we hand them, so the coercion and
    # same-time edge cases can be driven directly. Caching stays off (load_settings default).
    def config_returning start:, stop:
      described_class.new(
        possible_statuses: nil, label: 'foo', file_system: exporter.file_system, settings: settings,
        block: lambda do |_|
          start_at ->(_issue) { start }
          stop_at ->(_issue) { stop }
        end
      )
    end

    it 'fabricates a ChangeItem when a block returns a bare Time (legacy blocks)' do
      start = to_time('2025-01-03')
      stop = to_time('2025-01-05')
      started, stopped = config_returning(start: start, stop: stop).started_stopped_changes(issue)
      aggregate_failures do
        expect(started).to be_a(ChangeItem)
        expect(started.time).to eq start
        expect(stopped).to be_a(ChangeItem)
        expect(stopped.time).to eq stop
      end
    end

    it 'treats a block returning false as no start (false becomes nil, not a fabricated item)' do
      stop = to_time('2025-01-05')
      started, stopped = config_returning(start: false, stop: stop).started_stopped_changes(issue)
      aggregate_failures do
        expect(started).to be_nil
        expect(stopped.time).to eq stop
      end
    end

    it 'reports never-started when start and stop resolve to the same time' do
      same = to_time('2025-01-05')
      started, stopped = config_returning(start: same, stop: same).started_stopped_changes(issue)
      aggregate_failures do
        expect(started).to be_nil # same time -> pretend it never started
        expect(stopped).to be_a(ChangeItem)
        expect(stopped.time).to eq same
      end
    end

    it 'returns the start with no stop when the stop block finds nothing' do
      start = to_time('2025-01-03')
      started, stopped = config_returning(start: start, stop: nil).started_stopped_changes(issue)
      aggregate_failures do
        expect(started).to be_a(ChangeItem)
        expect(started.time).to eq start
        expect(stopped).to be_nil
      end
    end

    it 'caches each issue separately, so a second issue does not return the first issue result' do
      settings['cache_cycletime_calculations'] = true
      issue_a = empty_issue created: '2025-01-01', board: sample_board, key: 'SP-1'
      issue_a.changes.clear
      a_start = add_mock_change(issue: issue_a, field: 'status', value: 'In Progress', value_id: 3, time: '2025-01-03')
      a_stop = add_mock_change(issue: issue_a, field: 'status', value: 'Done', value_id: 10_002, time: '2025-01-05')
      issue_b = empty_issue created: '2025-01-01', board: sample_board, key: 'SP-2'
      issue_b.changes.clear
      b_start = add_mock_change(issue: issue_b, field: 'status', value: 'In Progress', value_id: 3, time: '2025-02-03')
      b_stop = add_mock_change(issue: issue_b, field: 'status', value: 'Done', value_id: 10_002, time: '2025-02-05')

      aggregate_failures do
        expect(cycletime.started_stopped_changes(issue_a)).to eq [a_start, a_stop]
        # A shared cache key would return issue_a's cached result here.
        expect(cycletime.started_stopped_changes(issue_b)).to eq [b_start, b_stop]
      end
    end

    it 'keys the cache by board id too, so the same issue on two boards does not collide' do
      settings['cache_cycletime_calculations'] = true
      board_a = sample_board
      board_a.raw['id'] = 2
      issue_a = empty_issue created: '2025-01-01', board: board_a, key: 'SP-1'
      issue_a.changes.clear
      a_start = add_mock_change(issue: issue_a, field: 'status', value: 'In Progress', value_id: 3, time: '2025-01-03')
      a_stop = add_mock_change(issue: issue_a, field: 'status', value: 'Done', value_id: 10_002, time: '2025-01-05')
      board_b = sample_board
      board_b.raw['id'] = 3
      issue_b = empty_issue created: '2025-01-01', board: board_b, key: 'SP-1'
      issue_b.changes.clear
      b_start = add_mock_change(issue: issue_b, field: 'status', value: 'In Progress', value_id: 3, time: '2025-02-03')
      b_stop = add_mock_change(issue: issue_b, field: 'status', value: 'Done', value_id: 10_002, time: '2025-02-05')

      aggregate_failures do
        expect(cycletime.started_stopped_changes(issue_a)).to eq [a_start, a_stop]
        # Same issue key, different board — dropping the board id from the cache key would collide.
        expect(cycletime.started_stopped_changes(issue_b)).to eq [b_start, b_stop]
      end
    end
  end
end
