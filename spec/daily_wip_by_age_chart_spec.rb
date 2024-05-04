# frozen_string_literal: true

require './spec/spec_helper'

describe DailyWipByAgeChart do
  context 'grouping_rules' do
    let(:chart) do
      chart = described_class.new nil
      chart.date_range = Date.parse('2022-01-01')..Date.parse('2022-02-01')
      chart
    end
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue 'SP-1', board: board }

    it 'handles active items with no start' do
      issue1.raw['fields']['created'] = to_time('2022-02-02').to_s
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, to_date('2022-01-05')]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-03')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Start date unknown', CssVariable['--body-background']]
      expect(rules.group_priority).to eq 11
    end

    it 'handles completed items with no start' do
      issue1.raw['fields']['created'] = to_time('2022-02-02').to_s
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, to_date('2022-01-05')]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-05')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Completed but not started', '#66FF66']
      expect(rules.group_priority).to eq(-1)
    end

    it 'completed today' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), to_date('2022-01-05')]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-05')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Completed', '#009900']
      expect(rules.group_priority).to eq(-2)
    end

    it 'active less than a day' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-01')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Less than a day', '#aaaaaa']
      expect(rules.group_priority).to eq 10
    end

    it 'active less than a week' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-07')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['A week or less', '#80bfff']
      expect(rules.group_priority).to eq 9
    end

    it 'active less than two weeks' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-14')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Two weeks or less', '#ffd700']
      expect(rules.group_priority).to eq 8
    end

    it 'active less than four weeks' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-28')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['Four weeks or less', '#ce6300']
      expect(rules.group_priority).to eq 7
    end

    it 'active more than four weeks' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_date('2022-01-01'), nil]
      ]
      rules = DailyGroupingRules.new
      rules.current_date = Date.parse('2022-01-29')
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.group).to eq ['More than four weeks', '#990000']
      expect(rules.group_priority).to eq 6
    end
  end
end
