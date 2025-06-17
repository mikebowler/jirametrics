# frozen_string_literal: true

require './spec/spec_helper'

describe DailyView do
  let(:view) do
    described_class.new(nil).tap do |view|
      view.date_range = to_date('2024-01-01')..to_date('2024-01-20')
      view.time_range = to_time('2024-01-01')..to_time('2024-01-20T23:59:59')
      view.settings = JSON.parse(File.read(File.join(['lib', 'jirametrics', 'settings.json']), encoding: 'UTF-8'))
    end
  end
  let(:board) { sample_board }

  context 'make_issue_header' do
    it 'creates for aging item' do
      issue = load_issue('SP-1', board: board)
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-01', nil]
      ]
      expect(view.make_issue_header issue).to eq [
        ["<b><a href='#{issue.url}'>SP-1</a></b> Create new draft event"],
        [
          "<img src='#{issue.type_icon_url}' /> <b>Story</b>",
          "<img src='#{issue.priority_url}' /> <b>Medium</b>",
          'Age: <b>20 days</b>',
          'Status: <b>In Progress</b>',
          'Column: <b>In Progress</b>'
        ],
        ["#{view.color_block '--blocked-color'} Blocked by flag"]
      ]
    end

    it 'creates for not started' do
      issue = load_issue('SP-1', board: board)
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, nil, nil]
      ]
      expect(view.make_issue_header issue).to eq [
        [
          "<b><a href='#{issue.url}'>SP-1</a></b> Create new draft event"
        ],
        [
          "<img src='#{issue.type_icon_url}' /> <b>Story</b>",
          "<img src='#{issue.priority_url}' /> <b>Medium</b>",
          'Status: <b>In Progress</b>',
          'Column: <b>In Progress</b>'
        ],
        ["#{view.color_block '--blocked-color'} Blocked by flag"]
      ]
    end

    it 'creates for finished' do
      issue = load_issue('SP-1', board: board)
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-02', '2024-01-02']
      ]
      expect(view.make_issue_header issue).to eq [
        ["<b><a href='#{issue.url}'>SP-1</a></b> Create new draft event"],
        [
          "<img src='#{issue.type_icon_url}' /> <b>Story</b>",
          "<img src='#{issue.priority_url}' /> <b>Medium</b>",
          'Status: <b>In Progress</b>',
          'Column: <b>In Progress</b>'
        ],
        ["#{view.color_block '--blocked-color'} Blocked by flag"]
      ]
    end
  end
end
