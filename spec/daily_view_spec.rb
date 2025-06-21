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
  let(:issue1) { load_issue('SP-1', board: board) }
  let(:issue2) { load_issue('SP-2', board: board) }
  let(:issue10) { load_issue('SP-10', board: board) }

  context 'select_aging_issues' do
    it 'selects only aging issues' do
      view.issues = [issue1, issue2, issue10]
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, '2024-01-01'],
        [issue2, nil, nil],
        [issue10, '2024-01-01', nil]
      ]
      expect(view.select_aging_issues).to eq [issue10]
    end
  end

  context 'issue_sorter' do
    it 'sorts by priority name first' do
      input = [
        [issue1, 'Lowest', 50],
        [issue2, 'Highest', 5]
      ]
      expect(input.sort(&view.issue_sorter)).to eq [
        [issue2, 'Highest', 5],
        [issue1, 'Lowest', 50]
      ]
    end

    it 'sorts by age when priorities match' do
      input = [
        [issue1, 'Lowest', 5],
        [issue2, 'Lowest', 50]
      ]
      expect(input.sort(&view.issue_sorter)).to eq [
        [issue2, 'Lowest', 50],
        [issue1, 'Lowest', 5]
      ]
    end

    it 'sorts unknown priorities after known' do
      input = [
        [issue1, 'Foo', 5],
        [issue2, 'Lowest', 50],
        [issue10, 'Bar', 1]
      ]
      expect(input.sort(&view.issue_sorter)).to eq [
        [issue2, 'Lowest', 50],
        [issue10, 'Bar', 1],
        [issue1, 'Foo', 5]
      ]
    end

    it 'sorts by key if all else fails' do
      input = [
        [issue1, 'Lowest', 1],
        [issue10, 'Lowest', 1],
        [issue2, 'Lowest', 1]
      ]
      expect(input.sort(&view.issue_sorter)).to eq [
        [issue1, 'Lowest', 1],
        [issue2, 'Lowest', 1],
        [issue10, 'Lowest', 1]
      ]
    end

  end

  context 'assemble_issue_lines' do
    it 'creates for aging item' do
      issue = load_issue('SP-1', board: board)
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-01', nil]
      ]
      expect(view.assemble_issue_lines issue).to eq [
        ["<b><a href='#{issue.url}'>SP-1</a></b> <i>Create new draft event</i>"],
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
      expect(view.assemble_issue_lines issue).to eq [
        [
          "<b><a href='#{issue.url}'>SP-1</a></b> <i>Create new draft event</i>"
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
      expect(view.assemble_issue_lines issue).to eq [
        ["<b><a href='#{issue.url}'>SP-1</a></b> <i>Create new draft event</i>"],
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

  context 'jira_rich_text_to_html' do
    it 'ignores plain text' do
      expect(view.jira_rich_text_to_html 'foobar').to eq 'foobar'
    end

    it 'converts color declarations' do
      input = 'one {color:#bf2600}bold Red{color} two ' \
        '{color:#403294}Bold purple{color} ' \
        'three {color:#b3f5ff}Subtle teal{color}'
      expect(view.jira_rich_text_to_html input).to eq(
        'one <span style="color: #bf2600">bold Red</span> ' \
        'two <span style="color: #403294">Bold purple</span> ' \
        'three <span style="color: #b3f5ff">Subtle teal</span>'
      )
    end
  end
end
