# frozen_string_literal: true

require './spec/spec_helper'

describe DailyWipByBlockedStalledChart do
  context 'grouping_rules' do
    let(:subject) do
      chart = DailyWipByBlockedStalledChart.new nil
      chart.date_range = Date.parse('2022-01-01')..Date.parse('2022-02-01')
      chart
    end
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue('SP-1', board: board).tap { |i| i.changes.clear } }

    it 'should handle active items with no start' do
      issue1.raw['fields']['created'] = to_time('2022-02-02').to_s
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, to_date('2022-01-05')]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-03')
      subject.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Start date unknown', 'white']
      expect(rules.group_priority).to eq 4
    end

    it 'is active' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      issue1.changes << mock_change(field: 'Status', value: 'Doing', time: to_time('2022-01-01'))
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-02')
      subject.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Active', 'lightgray'] # rubocop:disable Style/WordArray
      expect(rules.group_priority).to eq 3
    end

    it 'is blocked and not stalled' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: to_time('2022-01-01'))
      issue1.changes << mock_change(field: 'Flagged', value: 'Blocked', time: to_time('2022-01-01'))

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-02')
      subject.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Blocked', 'red'] # rubocop:disable Style/WordArray
      expect(rules.group_priority).to eq 1
    end

    it 'is stalled and not blocked' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: to_time('2022-01-01'))
      # issue1.changes << mock_change(field: 'Flagged', value: 'Blocked', time: to_time('2022-01-01'))

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-12')
      subject.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Stalled', 'orange'] # rubocop:disable Style/WordArray
      expect(rules.group_priority).to eq 2
    end

    it 'is both stalled and blocked' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      issue1.changes << mock_change(field: 'status', value: 'Doing', time: to_time('2022-01-01'))
      issue1.changes << mock_change(field: 'Flagged', value: 'Blocked', time: to_time('2022-01-01'))

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-12')
      subject.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Blocked', 'red'] # rubocop:disable Style/WordArray
      expect(rules.group_priority).to eq 1
    end
  end
end
