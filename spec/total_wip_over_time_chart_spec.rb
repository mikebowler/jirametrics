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
end
