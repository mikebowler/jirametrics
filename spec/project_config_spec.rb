# frozen_string_literal: true

require './spec/spec_helper'

describe ProjectConfig do
  context 'category_for' do
    it "where mapping doesn't exist" do
      config = ProjectConfig.new exporter: nil, target_path: nil, jira_config: nil, block: nil
      config.status_category_mapping type: 'Story', status: 'Doing', category: 'In progress'
      config.status_category_mapping type: 'Story', status: 'Done', category: 'Done'
      expect { config.category_for type: 'Epic', status: 'Foo', issue_id: 'SP-1' }
        .to raise_error(/^Could not determine a category for type/)
    end

    it 'where mapping does exist' do
      config = ProjectConfig.new exporter: nil, target_path: nil, jira_config: nil, block: nil
      config.status_category_mapping type: 'Story', status: 'Doing', category: 'InProgress'
      expect(config.category_for(type: 'Story', status: 'Doing', issue_id: 'SP-1')).to eql 'InProgress'
    end
  end

  it 'board_configuration' do
    config = ProjectConfig.new exporter: nil, target_path: 'spec/testdata/', jira_config: nil, block: nil
    config.file_prefix 'sample'
    config.load_all_board_configurations
    expect(config.all_board_columns.keys).to eq ['1']

    contents = config.all_board_columns['1'].collect do |column|
      [column.name, column.status_ids, column.min, column.max]
    end

    # rubocop:disable Layout/ExtraSpacing
    expect(contents).to eq [
      ['Backlog',     [10_000], nil, nil],
      ['Ready',       [10_001],   1,   4],
      ['In Progress',      [3], nil,   3],
      ['Review',      [10_011], nil,   3],
      ['Done',        [10_002], nil, nil]
    ]
    # rubocop:enable Layout/ExtraSpacing
  end
end
