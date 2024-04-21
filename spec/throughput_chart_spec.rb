# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/throughput_chart'

describe ThroughputChart do
  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:issue2) { load_issue 'SP-2', board: board }
  let(:issue10) { load_issue 'SP-10', board: board }

  context 'calculate_time_periods' do
    # October 11 is a Monday

    it 'returns empty list if no complete periods' do
      chart = described_class.new
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-13')
      expect(chart.calculate_time_periods).to be_empty
    end

    it 'works for a single period starting on a Monday' do
      chart = described_class.new
      chart.date_range = Date.parse('2021-10-11')..Date.parse('2021-10-18')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for a single period starting on a Sunday' do
      chart = described_class.new
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-17')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for a single period not starting on a Monday or Sunday' do
      chart = described_class.new
      chart.date_range = Date.parse('2021-10-05')..Date.parse('2021-10-19')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for multiple periods starting on a Monday' do
      chart = described_class.new
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-26')
      expect(chart.calculate_time_periods).to eq [
        Date.parse('2021-10-11')..Date.parse('2021-10-17'),
        Date.parse('2021-10-18')..Date.parse('2021-10-24')
      ]
    end
  end

  context 'throughput_dataset' do
    it 'returns correct data' do
      issue1.changes.clear
      issue1.changes << mock_change(field: 'resolution', value: 'done', time: '2021-10-12T01:00:00')

      issue2.changes.clear
      issue2.changes << mock_change(field: 'resolution', value: 'done', time: '2021-10-13T01:00:00')

      issue10.changes.clear

      subject = described_class.new
      subject.issues = [issue1, issue2, issue10]
      board.cycletime = default_cycletime_config

      dataset = subject.throughput_dataset(
        periods: [Date.parse('2021-10-11')..Date.parse('2021-10-17')],
        completed_issues: [issue1, issue2]
      )
      expect(dataset).to eq [
        {
          title: [
            '2 items completed between 2021-10-11 and 2021-10-17',
            'SP-1 : Create new draft event',
            'SP-2 : Update existing event'
          ],
          x: '2021-10-17T23:59:59',
          y: 2
        }
      ]
    end
  end

  context 'group_issues' do
    it 'renders when no rules specified' do
      expected_rules = GroupingRules.new
      expected_rules.color = 'green'
      expected_rules.label = 'Story'
      expect(described_class.new.group_issues([issue1])).to eq({
        expected_rules => [issue1]
      })
    end

    it 'renders when grouping_rules are used' do
      subject = described_class.new
      subject.grouping_rules do |issue, rules|
        if issue.key == 'SP-1'
          rules.color = 'orange'
          rules.label = 'foo'
        else
          rules.ignore
        end
      end
      expected_rules = GroupingRules.new
      expected_rules.color = 'orange'
      expected_rules.label = 'foo'
      expect(subject.group_issues([issue1, issue2])).to eq({
        expected_rules => [issue1]
      })
    end
  end
end
