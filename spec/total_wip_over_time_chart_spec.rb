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
      config = CycleTimeConfig.new parent_config: nil, label: nil, block: nil
      config.start_at ->(_issue) {}
      config.stop_at  ->(_issue) { Date.parse('2022-01-01') }
      chart.cycletime = config

      chart.issues = [issue1]
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
