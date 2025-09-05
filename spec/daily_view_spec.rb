# frozen_string_literal: true

require './spec/spec_helper'

describe DailyView do
  let(:view) do
    described_class.new(nil).tap do |view|
      view.date_range = to_date('2024-01-01')..to_date('2024-01-20')
      view.time_range = to_time('2024-01-01')..to_time('2024-01-20T23:59:59')
      view.settings = JSON.parse(File.read(File.join(['lib', 'jirametrics', 'settings.json']), encoding: 'UTF-8'))
      view.atlassian_document_format = AtlassianDocumentFormat.new(
        users: [], timezone_offset: '0000'
      )
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

  context 'make_title_line' do
    it 'is not expedited' do
      issue = load_issue('SP-1', board: board)
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-02', nil]
      ]

      expect(view.make_title_line issue: issue, done: false).to eq(
        "<img src='#{issue.type_icon_url}' title='Story' class='icon' /> " \
        "<b><a href='#{issue.url}'>SP-1</a></b> &nbsp;<i>Create new draft event</i>"
      )
    end

    it 'shows the expedited marker' do
      issue = load_issue('SP-1', board: board)
      issue.raw['fields']['priority'] = {
        'iconUrl' => 'https://improvingflow.atlassian.net/images/icons/priorities/highest_new.svg',
        'name' => 'Highest',
        'id' => '1'
      }
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-02', nil]
      ]
      expect(view.make_title_line issue: issue, done: false).to eq(
        "#{view.color_block('--expedited-color', title: 'Expedited')}" \
        "<img src='#{issue.type_icon_url}' title='Story' class='icon' /> " \
        "<b><a href='#{issue.url}'>SP-1</a></b> &nbsp;<i>Create new draft event</i>"
      )
    end
  end

  context 'make_parent_lines' do
    it 'returns nothing when no parent' do
      expect(view.make_parent_lines issue1).to be_empty
    end

    it 'returns key only when parent is not in issues list' do
      view.issues = IssueCollection[issue1]
      issue1.raw['fields']['parent'] = { 'key' => 'MISSING-123' }
      expect(view.make_parent_lines issue1).to eq [
        ['Parent: MISSING-123']
      ]
    end

    it 'returns link when parent is in issues list' do
      view.issues = IssueCollection[issue1, issue2]
      issue = load_issue('SP-1', board: board)
      issue.raw['fields']['parent'] = { 'key' => 'SP-2' }

      expect(view.make_parent_lines issue).to eq [
        [
          "Parent: <img src='#{issue2.type_icon_url}' title='Story' class='icon' /> " \
            "<b><a href='#{issue2.url}'>SP-2</a></b> &nbsp;<i>Update existing event</i>"
        ]
      ]
    end
  end

  context 'make_stats_lines' do
    it 'returns happy path' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-02', nil]
      ]

      status = board.possible_statuses.find_all_by_name('In Progress').first
      expect(view.make_stats_lines issue: issue1, done: false).to eq [
        [
          "<img src='#{issue1.priority_url}' class='icon' /> <b>Medium</b>",
          'Age: <b>19 days</b>',
          "Status: <b>#{view.format_status status, board: board}</b>",
          'Column: <b>In Progress</b>'
        ]
      ]
    end

    it 'returns not-started when appropriate' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil]
      ]

      status = board.possible_statuses.find_all_by_name('In Progress').first
      expect(view.make_stats_lines issue: issue1, done: false).to eq [
        [
          "<img src='#{issue1.priority_url}' class='icon' /> <b>Medium</b>",
          'Age: <b>(Not Started)</b>',
          "Status: <b>#{view.format_status status, board: board}</b>",
          'Column: <b>In Progress</b>'
        ]
      ]
    end

    it 'has labels' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil]
      ]
      issue1.raw['fields']['labels'] = ['foo']

      status = board.possible_statuses.find_all_by_name('In Progress').first
      expect(view.make_stats_lines issue: issue1, done: false).to eq [
        [
          "<img src='#{issue1.priority_url}' class='icon' /> <b>Medium</b>",
          'Age: <b>(Not Started)</b>',
          "Status: <b>#{view.format_status status, board: board}</b>",
          'Column: <b>In Progress</b>',
          "Labels: <span class='label'>foo</span>"
        ]
      ]
    end

    it 'has an assignee' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil]
      ]
      issue1.raw['fields']['assignee'] = {
        'displayName' => 'Fred Flintstone',
        'avatarUrls' => {
          '16x16' => 'http://example.com/fred.png'
        }
      }

      status = board.possible_statuses.find_all_by_name('In Progress').first
      expect(view.make_stats_lines issue: issue1, done: false).to eq [
        [
          "<img src='#{issue1.priority_url}' class='icon' /> <b>Medium</b>",
          'Age: <b>(Not Started)</b>',
          "Status: <b>#{view.format_status status, board: board}</b>",
          'Column: <b>In Progress</b>',
          "Assignee: <img src='http://example.com/fred.png' class='icon' /> <b>Fred Flintstone</b>"
        ]
      ]
    end

    it 'is in a status that is not on the board' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', nil]
      ]
      status = board.possible_statuses.find_all_by_name('Backlog').first
      issue1.raw['fields']['status'] = {
        'name' => status.name,
        'id' => status.id,
        'statusCategory' => {
          'id' => status.category.id,
          'key' => status.category.key,
          'name' => status.category.name
        }
      }

      expect(view.make_stats_lines issue: issue1, done: false).to eq [
        [
          "<img src='#{issue1.priority_url}' class='icon' /> <b>Medium</b>",
          'Age: <b>20 days</b>',
          "Status: <b>#{view.format_status status, board: board}</b>",
          'Column: <b>(not visible on board)</b>'
        ]
      ]
    end

    it 'has a due date' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil]
      ]
      issue1.raw['fields']['duedate'] = '2024-01-10'

      status = board.possible_statuses.find_all_by_name('In Progress').first
      expect(view.make_stats_lines issue: issue1, done: false).to eq [
        [
          "<img src='#{issue1.priority_url}' class='icon' /> <b>Medium</b>",
          'Age: <b>(Not Started)</b>',
          "Status: <b>#{view.format_status status, board: board}</b>",
          'Column: <b>In Progress</b>',
          'Due: <b>2024-01-10</b>'
        ]
      ]
    end
  end

  context 'make_blocked_stalled_lines' do
    it 'renders stalled by inactivity' do
      issue = empty_issue created: '2024-01-01'
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-01', nil]
      ]
      expect(view.make_blocked_stalled_lines issue).to eq [
        [
          "#{view.color_block '--stalled-color'} Stalled by inactivity: 19 days"
        ]
      ]
    end

    it 'renders stalled by status' do
      view.settings['stalled_statuses'] = ['Review']
      issue = empty_issue created: '2024-01-01'
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-01', nil]
      ]
      add_mock_change issue: issue, field: 'status', value: 'Review', time: '2024-01-03', value_id: 10_011

      expect(view.make_blocked_stalled_lines issue).to eq [
        [
          "#{view.color_block '--stalled-color'} Stalled by status: Review"
        ]
      ]
    end

    it 'renders blocked by status' do
      view.settings['blocked_statuses'] = ['Review']
      issue = empty_issue created: '2024-01-01'
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-01', nil]
      ]
      add_mock_change issue: issue, field: 'status', value: 'Review', time: '2024-01-03', value_id: 10_011

      expect(view.make_blocked_stalled_lines issue).to eq [
        [
          "#{view.color_block '--blocked-color'} Blocked by status: Review"
        ]
      ]
    end

    it 'renders blocked by issue' do
      view.settings['blocked_link_text'] = ['is blocked by']
      issue = empty_issue created: '2024-01-01'
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-01', nil]
      ]
      view.issues = [issue, issue2]
      add_mock_change(
        issue: issue, field: 'Link', value: 'This issue is blocked by SP-2', time: '2024-01-03', value_id: 10_011
      )

      expect(view.make_blocked_stalled_lines issue).to eq [
        ["#{view.color_block '--blocked-color'} Blocked by issue: SP-2"],
        issue2
      ]
    end

    it 'renders blocked by issue when blocker cannot be found' do
      view.settings['blocked_link_text'] = ['is blocked by']
      issue = empty_issue created: '2024-01-01'
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-01', nil]
      ]
      view.issues = [issue]
      add_mock_change(
        issue: issue, field: 'Link', value: 'This issue is blocked by SP-2', time: '2024-01-03', value_id: 10_011
      )

      expect(view.make_blocked_stalled_lines issue).to eq [
        [
          "#{view.color_block '--blocked-color'} Blocked by issue: SP-2"
        ]
      ]
    end
  end

  context 'history_text' do
    let(:review_status) { board.possible_statuses.find_by_id! 10_011 }
    let(:done_status) { board.possible_statuses.find_by_id! 10_002 }

    it 'is comment' do
      change = mock_change field: 'comment', value: 'foo', time: '2024-01-01'
      expect(view.history_text change: change, board: board).to eq 'foo'
    end

    it 'changes from no status to status' do
      change = mock_change field: 'status', value: review_status, time: '2024-01-01'
      expect(view.history_text change: change, board: board).to eq(
        "Set to #{view.format_status review_status, board: board}"
      )
    end

    it 'changes from one status to another' do
      change = mock_change field: 'status', value: done_status, old_value: review_status, time: '2024-01-01'
      expect(view.history_text change: change, board: board).to eq(
        "Changed from #{view.format_status review_status, board: board} " \
          "to #{view.format_status done_status, board: board}"
      )
    end

    it 'sets priority' do
      change = mock_change field: 'priority', value: 'Medium', value_id: 3, time: '2024-01-01'
      expect(view.history_text change: change, board: board).to eq(
        'Set to "Medium"'
      )
    end

    it 'sets flag on' do
      change = mock_change field: 'Flagged', value: 'Flagged', value_id: 3, time: '2024-01-01'
      expect(view.history_text change: change, board: board).to eq(
        'On'
      )
    end

    it 'sets flag off' do
      change = mock_change field: 'Flagged', value: '', value_id: 3, time: '2024-01-01'
      expect(view.history_text change: change, board: board).to eq(
        'Off'
      )
    end

    it 'sets some generic field' do
      change = mock_change field: 'estimatedtime', value: 'foo', value_id: 3, time: '2024-01-01'
      expect(view.history_text change: change, board: board).to eq(
        'foo'
      )
    end
  end

  context 'make_child_lines' do
    it 'returns empty for no children' do
      parent = empty_issue created: '2024-01-01', board: board
      expect(view.make_child_lines parent).to be_empty
    end

    it 'makes child lines' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', nil],
        [issue2, '2024-01-01', '2024-01-02']
      ]
      parent = empty_issue created: '2024-01-01', board: board
      parent.subtasks << issue1
      parent.subtasks << issue2

      expect(view.make_child_lines parent).to eq [
          '<section><div class="foldable">Child issues</div>',
          issue1,
          issue2,
          '</section>'
      ]
    end
  end

  context 'make_sprints_lines' do
    it 'returns empty if and it is not a scrum board' do
      board.raw['type'] = 'kanban'
      expect(view.make_sprints_lines issue1).to be_empty
    end

    it 'returns warning if there are no sprints and it is a scrum board' do
      board.raw['type'] = 'scrum'
      expect(view.make_sprints_lines issue1).to eq [
        ['Sprints: NONE']
      ]
    end

    it 'returns sprints' do
      board.raw['type'] = 'scrum'
      board.sprints << Sprint.new(timezone_offset: '00:00', raw: {
        'id' => 1,
        'state' => 'closed',
        'name' => 'Sprint 1'
      })
      board.sprints << Sprint.new(timezone_offset: '00:00', raw: {
        'id' => 2,
        'state' => 'active',
        'name' => 'Sprint 2'
      })
      add_mock_change issue: issue1, field: 'Sprint', value: 'Scrum Sprint 1', value_id: '1,2', time: '2024-01-01'
      expect(view.make_sprints_lines issue1).to eq [
        ["Sprints: <span class='label'><s>Sprint 1</s></span> <span class='label'>Sprint 2</span>"]
      ]
    end
  end
end
