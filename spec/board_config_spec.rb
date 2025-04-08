# frozen_string_literal: true

require './spec/spec_helper'

describe BoardConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:target_path) { 'spec/testdata/' }
  let(:project_config) do
    ProjectConfig.new exporter: exporter, target_path: target_path, jira_config: nil, block: nil
  end

  it 'raises error if cycletime set twice' do
    block = lambda do |_|
      cycletime do
        start_at first_time_in_status_category(:indeterminate)
        start_at first_time_in_status_category(:done)
      end
      cycletime do
        start_at first_time_in_status_category(:indeterminate)
        start_at first_time_in_status_category(:done)
      end
    end

    project_config.all_boards[1] = sample_board
    board_config = described_class.new project_config: project_config, id: 1, block: block

    expect { board_config.run }.to raise_error(
      'Cycletime has already been set for board 1. Did you also set it inside the html_report? ' \
        'If so, remove it from there.'
    )
  end

  it 'raises error if no cycletime is set' do
    project_config.all_boards[1] = sample_board
    board_config = described_class.new project_config: project_config, id: 1, block: empty_config_block

    expect { board_config.run }.to raise_error(
      'Must specify a cycletime for board 1'
    )
  end

  it 'sets expedited priority names (deprecated)' do
    board_config = described_class.new project_config: project_config, id: 1, block: empty_config_block
    board_config.expedited_priority_names 'super-high'

    expect(project_config.settings['expedited_priority_names']).to eq ['super-high']
    expect(exporter.file_system.log_messages).to match_strings [
      /^Deprecated\(2024-09-15\): Expedited priority names are now specified in settings/
    ]
  end
end
