# frozen_string_literal: true

require './spec/spec_helper'

describe BoardConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:target_path) { 'spec/testdata/' }
  let(:project_config) do
    ProjectConfig.new exporter: exporter, target_path: target_path, jira_config: nil, block: nil
  end

  it 'sets expedited names' do
    project_config.all_boards[1] = sample_board
    board_config = described_class.new project_config: project_config, id: 1, block: ->(_) {}
    board_config.run
    board_config.expedited_priority_names 'Highest', 'Critical'
    expect(board_config.board.expedited_priority_names).to eq %w[Highest Critical]
  end

  it 'raises error if cycletime set twice' do
    project_config.all_boards[1] = sample_board
    board_config = described_class.new project_config: project_config, id: 1, block: ->(_) {}
    board_config.run

    board_config.cycletime default_cycletime_config

    expect { board_config.cycletime default_cycletime_config }.to raise_error(
      'Cycletime has already been set for board 1. Did you also set it inside the html_report? ' \
        'If so, remove it from there.'
    )
  end
end
