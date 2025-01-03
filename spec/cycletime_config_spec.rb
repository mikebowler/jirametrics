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
        parent_config: project_config, label: 'foo', file_system: exporter.file_system, block: lambda do |_|
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
        parent_config: project_config, label: 'foo', file_system: exporter.file_system, block: lambda do |_|
          start_at first_time_in_status('In Progress')
          stop_at first_time_in_status('Done')
        end
      )
      config.stopped_time issue
      expect(exporter.file_system.log_messages).to match_strings [
        /Deprecated\(2024-10-16\): Use started_stopped_times\(\) instead/
      ]
    end
  end
end
