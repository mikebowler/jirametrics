# frozen_string_literal: true

require './spec/spec_helper'

describe BlockedStalledChart do
  context 'blocked_stalled' do
    it 'should handle nothing blocked or stalled' do
      issue1 = load_issue('SP-1')
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'ToDo',  time: '2021-10-01', artificial: true)
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: '2021-10-02')
      issue1.raw['fields']['updated'] = '2021-10-02' # Stalled logic uses this field.

      subject = BlockedStalledChart.new
      subject.cycletime = defaultCycletimeConfig

      expected_blocked = []
      expected_stalled = []
      expect(subject.blocked_stalled date: Date.parse('2021-10-04'), issues: [issue1], stalled_threshold: 5).to eq [
        expected_blocked, expected_stalled
      ]
    end

    it 'should handle something blocked only' do
      issue1 = load_issue('SP-1')
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'ToDo',  time: '2021-10-01', artificial: true)
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: '2021-10-02')
      issue1.changes << mock_change(field: 'Flagged', value: 'Flagged', time: '2021-10-03')
      issue1.raw['fields']['updated'] = '2021-10-03' # Stalled logic uses this field.

      subject = BlockedStalledChart.new
      subject.cycletime = defaultCycletimeConfig

      expected_blocked = [issue1]
      expected_stalled = []
      expect(subject.blocked_stalled date: Date.parse('2021-10-04'), issues: [issue1], stalled_threshold: 5).to eq [
        expected_blocked, expected_stalled
      ]
    end

    it 'should handle something stalled only' do
      issue1 = load_issue('SP-1')
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'ToDo',  time: '2021-10-01', artificial: true)
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: '2021-10-02')
      issue1.raw['fields']['updated'] = '2021-10-03' # Stalled logic uses this field.

      subject = BlockedStalledChart.new
      subject.cycletime = defaultCycletimeConfig

      expected_blocked = []
      expected_stalled = [issue1]
      expect(subject.blocked_stalled date: Date.parse('2021-10-14'), issues: [issue1], stalled_threshold: 5).to eq [
        expected_blocked, expected_stalled
      ]
    end

    it 'should mark an issue as only blocked when it\'s both blocked and stalled' do
      issue1 = load_issue('SP-1')
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'ToDo',  time: '2021-10-01', artificial: true)
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: '2021-10-02')
      issue1.changes << mock_change(field: 'Flagged', value: 'Flagged', time: '2021-10-03')
      issue1.raw['fields']['updated'] = '2021-10-03' # Stalled logic uses this field.

      subject = BlockedStalledChart.new
      subject.cycletime = defaultCycletimeConfig

      expected_blocked = [issue1]
      expected_stalled = []
      expect(subject.blocked_stalled date: Date.parse('2021-10-14'), issues: [issue1], stalled_threshold: 5).to eq [
        expected_blocked, expected_stalled
      ]
    end
  end
end
