# frozen_string_literal: true

require './spec/spec_helper'

def flatten_issue_groups issue_rules_by_active_dates
  result = []
  issue_rules_by_active_dates.keys.sort.each do |date|
    issue_rules_by_active_dates[date].each do |issue, rules|
      result << [date.to_s, issue.key, rules.label, rules.color, rules.group_priority]
    end
  end
  result
end

describe DailyWipChart do
  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:issue2) { load_issue 'SP-2', board: board }

  let(:subject) do
    empty_config_block = ->(_) {}
    chart = DailyWipChart.new empty_config_block
    chart.date_range = Date.parse('2022-01-01')..Date.parse('2022-04-02')
    chart
  end

  context 'group_issues_by_active_dates' do
    it 'should return nothing when no issues' do
      subject.issues = []
      expect(subject.group_issues_by_active_dates).to be_empty
    end

    it 'should return raise exception when no grouping rules set' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      subject.issues = [issue1]
      expect { subject.group_issues_by_active_dates }.to raise_error('grouping_rules must be set')
    end

    it 'should return nothing when grouping rules ignore everything' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      subject.issues = [issue1]
      subject.grouping_rules do |_issue, rules|
        rules.ignore
      end
      expect(subject.group_issues_by_active_dates).to be_empty
    end

    it 'should make a single group for one issue' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      subject.issues = [issue1]
      subject.grouping_rules do |_issue, rules|
        rules.label = 'foo'
        rules.color = 'blue'
      end

      expect(flatten_issue_groups subject.group_issues_by_active_dates).to eq([
        ['2022-02-02', 'SP-1', 'foo', 'blue', 0]
      ])
    end

    it 'should skip and issue that neither started nor stopped' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil]
      ]
      subject.issues = [issue1]
      subject.grouping_rules do |_issue, rules|
        rules.label = 'foo'
        rules.color = 'blue'
      end

      expect(flatten_issue_groups subject.group_issues_by_active_dates).to be_empty
    end

    it 'should include an issue that stopped but never started' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, to_time('2022-01-03T14:00:00')]
      ]
      subject.issues = [issue1]
      subject.grouping_rules do |_issue, rules|
        rules.label = 'foo'
        rules.color = 'blue'
      end

      expect(flatten_issue_groups subject.group_issues_by_active_dates).to eq([
        ['2022-01-01', 'SP-1', 'foo', 'blue', 0],
        ['2022-01-02', 'SP-1', 'foo', 'blue', 0],
        ['2022-01-03', 'SP-1', 'foo', 'blue', 0]
      ])
    end
  end

  context 'select_possible_rules' do
    it 'should return empty for no data' do
      expect(subject.select_possible_rules issue_rules_by_active_date: {}).to be_empty
    end

    it 'should return one group' do
      rules = DailyGroupingRules.new
      rules.label = 'foo'
      rules.color = 'red'
      rules.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rules]
        ]
      }
      expect(subject.select_possible_rules(issue_rules_by_active_date).collect(&:group)).to eq([
        %w[foo red]
      ])
    end

    it 'should return two different groups' do
      rule1 = DailyGroupingRules.new
      rule1.label = 'foo'
      rule1.color = 'red'
      rule1.group_priority = 0

      rule2 = DailyGroupingRules.new
      rule2.label = 'bar'
      rule2.color = 'gray'
      rule2.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule1],
          [issue2, rule2]
        ]
      }
      expect(subject.select_possible_rules(issue_rules_by_active_date).collect(&:group)).to eq([
        %w[foo red],
        %w[bar gray]
      ])
    end

    it 'should return one group when the same one is used twice' do
      rule1 = DailyGroupingRules.new
      rule1.label = 'foo'
      rule1.color = 'red'
      rule1.group_priority = 0

      rule2 = DailyGroupingRules.new
      rule2.label = 'foo'
      rule2.color = 'red'
      rule2.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule1],
          [issue2, rule2]
        ]
      }
      expect(subject.select_possible_rules(issue_rules_by_active_date).collect(&:group)).to eq([
        %w[foo red]
      ])
    end
  end

  context 'make_data_set' do
    it 'positive' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = 'red'
      rule.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule],
          [issue2, rule]
        ]
      }

      data_set = subject.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      expect(data_set).to eq({
        backgroundColor: 'red',
        borderColor: 'gray',
        borderRadius: 0,
        borderWidth: 0,
        data: [
          {
            title: ['foo (2 issues)', 'SP-1 : Create new draft event ', 'SP-2 : Update existing event '],
            x: to_date('2022-01-01'),
            y: 2
          }
        ],
        label: 'foo',
        type: 'bar'
      })
    end

    it 'negative' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = 'white'
      rule.group_priority = -1

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule],
          [issue2, rule]
        ]
      }

      data_set = subject.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      expect(data_set).to eq({
        backgroundColor: 'white',
        borderColor: 'gray',
        borderRadius: 5,
        borderWidth: 1,
        data: [
          {
            title: ['foo (2 issues)', 'SP-1 : Create new draft event ', 'SP-2 : Update existing event '],
            x: to_date('2022-01-01'),
            y: -2
          }
        ],
        label: 'foo',
        type: 'bar'
      })
    end
  end
end
