# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkTable do
  let(:table) do
    described_class.new(nil).tap do |table|
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
  end
end
