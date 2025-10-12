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

  context 'deprecated' do
    it 'deprecates started_at' do
      config = described_class.new(
        parent_config: project_config, label: 'foo', file_system: exporter.file_system, settings: load_settings,
        block: lambda do |_|
          start_at first_time_in_status('In Progress')
          stop_at first_time_in_status('Done')
        end
      )
      config.started_time issue
      expect(exporter.file_system.log_messages).to match_strings [
        /Deprecated\(2024-10-16\): Use started_stopped_times\(\) instead/
      ]
    end

    it 'deprecates stopped_at' do
      config = described_class.new(
        parent_config: project_config, label: 'foo', file_system: exporter.file_system, settings: load_settings,
        block: lambda do |_|
          start_at first_time_in_status('In Progress')
          stop_at first_time_in_status('Done')
        end
      )
      config.stopped_time issue
      expect(exporter.file_system.log_messages).to match_strings [
        /Deprecated\(2024-10-16\): Use started_stopped_times\(\) instead/
      ]
    end

    it 'deprecates methods that return a time' do
      config = described_class.new(
        parent_config: project_config, label: 'foo', file_system: exporter.file_system, settings: load_settings,
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

  context 'started_stopped_changes caching' do
    let(:settings) { load_settings }
    let(:cycletime) do
      described_class.new(
        parent_config: project_config,
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
  end
end
