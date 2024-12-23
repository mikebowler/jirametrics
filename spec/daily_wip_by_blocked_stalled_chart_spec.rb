# frozen_string_literal: true

require './spec/spec_helper'

describe DailyWipByBlockedStalledChart do
  context 'grouping_rules' do
    let(:chart) do
      chart = described_class.new nil
      chart.date_range = to_date('2022-01-01')..to_date('2022-02-01')
      chart.time_range = to_time('2022-01-01')..to_time('2022-02-01T23:59:59')
      chart
    end
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue('SP-1', board: board).tap { |i| i.changes.clear } }

    it 'handles active items with no start' do
      issue1.raw['fields']['created'] = to_time('2022-02-02').to_s
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, to_date('2022-01-05')]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-03')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Start date unknown', CssVariable['--body-background']]
      expect(rules.group_priority).to eq 4
    end

    it 'is active' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      add_mock_change(issue: issue1, field: 'Status', value: 'Doing', time: to_time('2022-01-01'))
      chart.time_range = to_time('2022-01-01')..to_time('2022-01-03')

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-02')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Active', CssVariable['--wip-chart-active-color']]
      expect(rules.group_priority).to eq 3
    end

    it 'is blocked and not stalled' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: to_time('2022-01-01'))
      add_mock_change(issue: issue1, field: 'Flagged', value: 'Blocked', time: to_time('2022-01-01'))
      chart.time_range = to_time('2022-01-01')..to_time('2022-01-03')

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-02')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Blocked', CssVariable['--blocked-color']]
      expect(rules.group_priority).to eq 1
    end

    it 'is stalled and not blocked' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: to_time('2022-01-01'))
      chart.time_range = to_time('2022-01-01')..to_time('2022-01-13')

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-12')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Stalled', CssVariable['--stalled-color']]
      expect(rules.group_priority).to eq 2
    end

    it 'is both stalled and blocked' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: to_time('2022-01-01'))
      add_mock_change(issue: issue1, field: 'Flagged', value: 'Blocked', time: to_time('2022-01-01'))

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-01')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Blocked', CssVariable.new('--blocked-color')]
      expect(rules.group_priority).to eq 1
    end

    it 'is completed' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), to_date('2022-01-02')]
      ]
      chart.time_range = to_time('2022-01-01')..to_time('2022-01-03')

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-02')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Completed', CssVariable['--wip-chart-completed-color']]
      expect(rules.group_priority).to eq(-2)
    end

    it 'is completed, without being started' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, to_date('2022-01-02')]
      ]
      chart.time_range = to_time('2022-01-01')..to_time('2022-01-03')

      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-02')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq [
        'Completed but not started', CssVariable['--wip-chart-completed-but-not-started-color']
      ]
      expect(rules.group_priority).to eq(-1)
    end
  end
end
