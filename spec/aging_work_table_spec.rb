# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkTable do
  let(:table) do
    AgingWorkTable.new('Highest', nil).tap do |table|
      table.date_range = Date.parse('2021-01-01')..Date.parse('2021-01-31')
      table.today = table.date_range.end + 1
    end
  end

  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue('SP-1', board: board).tap { |issue| issue.changes.clear } }
  let(:issue2) { load_issue('SP-2', board: board).tap { |issue| issue.changes.clear } }

  context 'icon_span' do
    it 'should work' do
      expect(table.icon_span title: 'foo', icon: 'x').to eq "<span title='foo' style='font-size: 0.8em;'>x</span>"
    end
  end

  context 'expedited_text' do
    it 'should be empty when not expedited' do
      issue1.raw['fields']['priority']['name'] = 'Not set'
      expect(table.expedited_text issue1).to be_nil
    end

    it 'should work when expedited' do
      issue1.raw['fields']['priority']['name'] = 'Highest'
      expect(table.expedited_text issue1).to eq(
        table.icon_span title: 'Expedited: Has a priority of &quot;Highest&quot;', icon: '🔥'
      )
    end
  end

  context 'blocked_text' do
    it 'should handle simple blocked' do
      issue1.changes << mock_change(field: 'Flagged', value: 'Blocked', time: '2020-10-03')
      expect(table.blocked_text issue1).to eq(table.icon_span title: 'Blocked: Has the flag set', icon: '🛑')
    end

    it 'should handle stalled' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2022-10-04', nil]]
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: '2022-10-04')
      table.today = to_date('2022-10-15')

      expect(table.blocked_text issue1).to eq(
        table.icon_span(
          title: 'Stalled: Hasn&apos;t had any activity in 11 days and isn&apos;t explicitly marked as blocked',
          icon: '🟧'
        )
      )
    end

    it 'should handle dead' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2022-10-04', nil]]
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: '2022-10-04')
      table.today = to_date('2022-12-01')

      expect(table.blocked_text issue1).to eq(
        table.icon_span(
          title: 'Dead? Hasn&apos;t had any activity in 58 days. Does anyone still care about this?',
          icon: '⬛'
        )
      )
    end

    it 'should handle started but neither blocked nor stalled' do
      issue1.changes << mock_change(field: 'status', value: 'doing', time: (table.today - 1).to_time)
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2021-01-01', nil]]
      expect(table.blocked_text issue1).to be_nil
    end

    it 'should handle not started and also neither blocked nor stalled' do
      issue1.changes << mock_change(field: 'status', value: 'doing', time: (table.today - 1).to_time)
      board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, nil]]
      expect(table.blocked_text issue1).to be_nil
    end
  end

  context 'select_aging_issues' do
    it 'should handle no issues' do
      table.issues = []
      expect(table.select_aging_issues).to be_empty
    end

    it 'should handle a single aging issue' do
      board.cycletime = mock_cycletime_config stub_values: [[issue1, '2021-01-02', nil]]
      table.issues = [issue1]
      expect(table.select_aging_issues).to eq [issue1]
    end

    it 'should handle a mix of aging and completed' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2021-01-02', nil],
        [issue2, '2021-01-02', '2021-010-04']
      ]
      table.issues = [issue1, issue2]
      expect(table.select_aging_issues).to eq [issue1]
    end
  end
end
