# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkTable do
  let(:table) do
    described_class.new(empty_config_block).tap do |table|
      table.date_range = to_date('2021-01-01')..to_date('2021-01-31')
      table.time_range = to_time('2021-01-01')..to_time('2021-01-31T23:59:59')
      table.today = table.date_range.end + 1
    end
  end

  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue('SP-1', board: board).tap { |issue| issue.changes.clear } }
  let(:issue2) { load_issue('SP-2', board: board).tap { |issue| issue.changes.clear } }

  context 'icon_span' do
    it 'creates span' do
      expect(table.icon_span title: 'foo', icon: 'x').to eq "<span title='foo' style='font-size: 0.8em;'>x</span>"
    end
  end

  context 'expedited_text' do
    it 'is empty when not expedited' do
      issue1.raw['fields']['priority']['name'] = 'Not set'
      expect(table.expedited_text issue1).to be_nil
    end

    it 'creates span when expedited' do
      issue1.raw['fields']['priority']['name'] = 'Highest'
      issue1.board.expedited_priority_names = ['Highest']
      expect(table.expedited_text issue1).to eq(
        "<div class='color_block' style='background: var(--expedited-color);' " \
          'title="Expedited: Has a priority of &quot;Highest&quot;"></div>'
      )
    end
  end

  context 'blocked_text' do
    it 'handles flagged' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2020-10-02', nil]]
      issue1.changes << mock_change(field: 'Flagged', value: 'Blocked', time: '2020-10-03')
      expect(table.blocked_text issue1).to eq(
        "<div class='color_block' style='background: var(--blocked-color);' title=\"Blocked by flag\"></div>"
      )
    end

    it 'handles blocked status' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2022-10-04', nil]]
      review_status = issue1.board.possible_statuses.find { |s| s.name == 'Review' }

      issue1.board.project_config.settings['blocked_statuses'] = [review_status.name]
      issue1.changes << mock_change(field: 'status', value: review_status, time: '2020-10-03')
      table.time_range = table.time_range.begin..to_time('2022-10-15')

      expect(table.blocked_text issue1).to eq(
        "<div class='color_block' style='background: var(--blocked-color);' " \
          'title="Blocked by status: Review"></div>'
      )
    end

    it 'handles stalled' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2022-10-04', nil]]
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: '2022-10-04')
      table.time_range = table.time_range.begin..to_time('2022-10-15')

      expect(table.blocked_text issue1).to eq(
        "<div class='color_block' style='background: var(--stalled-color);' " \
          'title="Stalled by inactivity: 11 days"></div>'
      )
    end

    it 'handles dead' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2022-10-04', nil]]
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: '2022-10-04')
      table.time_range = table.time_range.begin..to_time('2022-12-01')

      expect(table.blocked_text issue1).to eq(
        "<div class='color_block' style='background: var(--dead-color);' " \
          'title="Dead? Hasn&apos;t had any activity in 58 days. Does anyone still care about this?"></div>'
      )
    end

    it 'handles started but neither blocked nor stalled' do
      issue1.changes << mock_change(field: 'status', value: 'doing', time: (table.today - 1).to_time)
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2021-01-01', nil]]
      expect(table.blocked_text issue1).to be_nil
    end

    it 'handles not started and also neither blocked nor stalled' do
      issue1.changes << mock_change(field: 'status', value: 'doing', time: (table.today - 1).to_time)
      board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, nil]]
      expect(table.blocked_text issue1).to be_nil
    end
  end

  context 'select_aging_issues' do
    it 'handles no issues' do
      table.issues = []
      expect(table.select_aging_issues).to be_empty
    end

    it 'handles a single aging issue' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2021-01-02', nil]]
      table.issues = [issue1]
      expect(table.select_aging_issues).to eq [issue1]
    end

    it 'handles a mix of aging and completed' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2021-01-02', nil],
        [issue2, '2021-01-02', '2021-010-04']
      ]
      table.issues = [issue1, issue2]
      expect(table.select_aging_issues).to eq [issue1]
    end

    it 'ignores issues younger than the cutoff' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2021-01-02', nil]]
      table.age_cutoff 5
      table.today = to_date '2021-01-03'
      table.issues = [issue1]
      expect(table.select_aging_issues).to be_empty
      expect(table.age_cutoff).to eq 5 # Pull it back out just to verify that we can.
    end
  end

  context 'fix_versions_text' do
    it 'returns blank when no fix versions' do
      expect(table.fix_versions_text issue1).to eq ''
    end

    it 'returns correctly with a mix of fix versions' do
      issue1.fix_versions << FixVersion.new({'name' => 'One', 'released' => false})
      issue1.fix_versions << FixVersion.new({'name' => 'Two', 'released' => true})
      expect(table.fix_versions_text issue1).to eq(
        "One<br />Two <span title='Released. Likely not on the board anymore.' style='font-size: 0.8em;'>✅</span>"
      )
    end
  end

  context 'sprints_text' do
    it 'returns empty when no sprints' do
      expect(table.sprints_text issue1).to eq ''
    end

          # {
          #   "field": "Sprint",
          #   "fieldtype": "custom",
          #   "fieldId": "customfield_10020",
          #   "from": "7",
          #   "fromString": "Scrum Sprint 7",
          #   "to": "7, 8",
          #   "toString": "Scrum Sprint 7, Scrum Sprint 8"
          # }

    it 'returns when one active sprint' do
      # Put a non-sprint change there to ensure it doesn't blow up on those
      issue1.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-10-02')
      issue1.changes << mock_change(field: 'Sprint', value: 'Sprint1', value_id: "2", time: '2020-10-03')

      issue1.board.sprints << Sprint.new(timezone_offset: '+00:00', raw: {
        'id' => 2, 'state' => 'active', 'name' => 'Sprint1'
      })
      expect(table.sprints_text issue1).to eq(
        "Sprint1 <span title='Active sprint' style='font-size: 0.8em;'>➡️</span>"
      )
    end

    it 'returns when multiple sprint' do
      # Put a non-sprint change there to ensure it doesn't blow up on those
      issue1.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-10-02')
      issue1.changes << mock_change(field: 'Sprint', value: 'Sprint1, Sprint2', value_id: "2, 3", time: '2020-10-03')

      issue1.board.sprints << Sprint.new(timezone_offset: '+00:00', raw: {
        'id' => 2, 'state' => 'active', 'name' => 'Sprint1'
      })
      issue1.board.sprints << Sprint.new(timezone_offset: '+00:00', raw: {
        'id' => 3, 'state' => 'inactive', 'name' => 'Sprint2'
      })
      expect(table.sprints_text issue1).to eq(
        "Sprint1 <span title='Active sprint' style='font-size: 0.8em;'>➡️</span><br />" \
          "Sprint2 <span title='Sprint closed' style='font-size: 0.8em;'>✅</span>"
      )
    end
  end

  context 'parent_hierarchy' do
    it 'works when no parent' do
      expect(table.parent_hierarchy(issue1)).to eq [issue1]
    end

    it 'handles simple hierarchy' do
      issue1.parent = issue2
      expect(table.parent_hierarchy(issue1)).to eq [issue2, issue1]
    end

    it 'handles recursive loops' do
      issue1.parent = issue2
      issue2.parent = issue1
      expect(table.parent_hierarchy(issue1)).to eq [issue1, issue2, issue1]
    end
  end

  it 'should find expedited_but_not_started' do
    issue3 = empty_issue key: 'SP-3', created: '2024-01-01', board: board
    # issue3.changes << mock_change(field: 'Priority', value: 'Highest', time: '2024-01-02')
    issue3.raw['fields']['priority'] = {'name' => 'Highest'}

    board.cycletime = mock_cycletime_config stub_values: [
      [issue1, nil, nil],
      [issue2, nil, nil],
      [issue3, nil, nil],
    ]
    board.expedited_priority_names = ['Highest']
    table.issues = [issue1, issue2, issue3]

    expect(table.expedited_but_not_started).to eq [issue3]
  end
end
