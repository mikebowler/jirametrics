# frozen_string_literal: true

require './spec/spec_helper'

describe BoardConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:target_path) { 'spec/testdata/' }
  let(:project_config) do
    ProjectConfig.new exporter: exporter, target_path: target_path, jira_config: nil, block: nil
  end

  it 'raises error if cycletime set twice' do
    project_config.all_boards[1] = sample_board
    board_config = described_class.new project_config: project_config, id: 1, block: empty_config_block
    board_config.run

    board_config.cycletime default_cycletime_config

    expect { board_config.cycletime default_cycletime_config }.to raise_error(
      'Cycletime has already been set for board 1. Did you also set it inside the html_report? ' \
        'If so, remove it from there.'
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
