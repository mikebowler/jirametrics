# frozen_string_literal: true

require './spec/spec_helper'

describe HierarchyTable do
  it 'initializes for no issues' do
    table = described_class.new ->(_) { description_text 'foo' }
    table.issues = []
    table.run
    expect(table.description_text).to eq(
      'foo'
    )
  end

  it 'identifies cyclical dependencies' do
    board = load_complete_sample_board
    issue1 = load_issue('SP-1', board: board)
    issue2 = load_issue('SP-2', board: board)

    board.cycletime = mock_cycletime_config stub_values: [
      [issue1, nil, nil],
      [issue2, nil, nil]
    ]

    issue1.parent = issue2
    issue2.parent = issue1

    table = described_class.new empty_config_block
    table.issues = [issue1, issue2]
    table.run
    expect(table.description_text.strip).to eq(
      '<p>Shows all issues through this time period and the full hierarchy of their parents.</p>' \
        "\n" \
        '<p>Found cyclical links in the parent hierarchy. This is an error and should be fixed.</p>' \
        '<ul><li>SP-2 > SP-1</ul></ul>'
    )
  end
end
