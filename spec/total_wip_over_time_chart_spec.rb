# frozen_string_literal: true

require './spec/spec_helper'

describe TotalWipOverTimeChart do
  let(:issue1)  { load_issue 'SP-1' }
  let(:issue2)  { load_issue 'SP-2' }
  let(:issue10) { load_issue 'SP-10' }

  let :chart do
    chart = TotalWipOverTimeChart.new
    chart.cycletime = defaultCycletimeConfig
    chart
  end

  context 'completed_but_not_started_dataset' do
    it 'should handle none like this' do
      chart.issues = []
      expect(chart.completed_but_not_started_dataset).to eq({
        backgroundColor: '#66FF66',
        borderRadius: 5,
        data: [],
        label: 'Completed without having been started',
        type: 'bar'
      })
    end

    it 'should handle one like this' do
      chart.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, '2022-01-01'], # finished but not started
        [issue2, '2022-01-01', nil] # Started but not finished
      ]

      chart.issues = [issue1, issue2]
      expect(chart.completed_but_not_started_dataset).to eq({
        backgroundColor: '#66FF66',
        borderRadius: 5,
        data: [
          {
            title: ['Completed without having been started (1 issue)', 'SP-1 : Create new draft event'],
            x: Date.parse('2022-01-01'),
            y: -1
          }
        ],
        label: 'Completed without having been started',
        type: 'bar'
      })
    end
  end

  context 'completed' do
    it 'should handle none like this' do
      chart.instance_variable_set(:@daily_chart_items, [])

      expect(chart.completed_dataset).to eq({
        backgroundColor: '#009900',
        borderRadius: 5,
        data: [],
        label: 'Completed',
        type: 'bar'
      })
    end

    it 'should handle one like this' do
      chart.instance_variable_set(:@daily_chart_items, [
        DailyChartItemGenerator::DailyChartItem.new(date: Date.parse('2022-01-03'), completed_issues: [issue1])
      ])
      expect(chart.completed_dataset).to eq({
        backgroundColor: '#009900',
        borderRadius: 5,
        data: [
          {
            title: ['Completed (1 issue)', 'SP-1 : Create new draft event'],
            x: Date.parse('2022-01-03'),
            y: -1
          }
        ],
        label: 'Completed',
        type: 'bar'
      })
    end
  end

  context 'age_range_dataset' do
    it 'should handle none like this' do
      chart.instance_variable_set(:@daily_chart_items, [])

      expect(chart.age_range_dataset age_range: 1..3, color: 'red', label: 'foo').to eq({
        backgroundColor: 'red',
        borderRadius: 0,
        data: [],
        label: 'foo',
        type: 'bar'
      })
    end

    it 'should handle one like this' do
      chart.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2022-01-01', '2022-01-03'], # Inside the range
        [issue2, '2021-12-01', '2022-02-03']  # Outside the range
      ]
      chart.instance_variable_set(:@daily_chart_items, [
        DailyChartItemGenerator::DailyChartItem.new(
          date: Date.parse('2022-01-03'), active_issues: [issue1, issue2], completed_issues: []
        )
      ])
      expect(chart.age_range_dataset age_range: 1..3, color: 'red', label: 'foo').to eq({
        backgroundColor: 'red',
        borderRadius: 0,
        data: [
          {
            title: ['foo (1 issue)', 'SP-1 : Create new draft event (age: 3 days)'],
            x: Date.parse('2022-01-03'),
            y: 1
          }
        ],
        label: 'foo',
        type: 'bar'
      })
    end
  end
end
