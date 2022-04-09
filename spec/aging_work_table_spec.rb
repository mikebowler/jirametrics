# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkTable do
  let(:table) do
    AgingWorkTable.new('Highest').tap do |table|
      table.date_range = Date.parse('2021-01-01')..Date.parse('2021-01-31')
      table.today = table.date_range.end + 1
    end
  end

  let(:issue) do
    load_issue('SP-1').tap do |issue|
      issue.changes.clear
    end
  end

  context 'icon_span' do
    it 'should work' do
      expect(table.icon_span title: 'foo', icon: 'x').to eq "<span title='foo' style='font-size: 0.8em;'>x</span>"
    end
  end

  context 'expedited_text' do
    it 'should be empty when not expedited' do
      issue.raw['fields']['priority']['name'] = 'Not set'
      expect(table.expedited_text issue).to be_nil
    end

    it 'should work when expedited' do
      issue.raw['fields']['priority']['name'] = 'Highest'
      expect(table.expedited_text issue).to eq(table.icon_span title: 'Expedited', icon: '🔥')
    end
  end

  context 'blocked_text' do
    it 'should handle simple blocked' do
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked', time: '2020-10-03')
      expect(table.blocked_text issue).to eq(table.icon_span title: 'Blocked', icon: '🛑')
    end

    it 'should handle stalled' do
      table.cycletime = mock_cycletime_config stub_values: { issue => 10 }
      expect(table.blocked_text issue).to eq(table.icon_span title: 'Stalled', icon: '🟧')
    end

    it 'should handle started but neither blocked nor stalled' do
      issue.changes << mock_change(field: 'status', value: 'doing', time: (table.today - 1).to_time)
      table.cycletime = mock_cycletime_config stub_values: { issue => ['2021-01-01', nil] }
      expect(table.blocked_text issue).to be_nil
    end

    it 'should handle not started and also neither blocked nor stalled' do
      issue.changes << mock_change(field: 'status', value: 'doing', time: (table.today - 1).to_time)
      table.cycletime = mock_cycletime_config stub_values: { issue => [nil, nil] }
      expect(table.blocked_text issue).to be_nil
    end
  end
end
