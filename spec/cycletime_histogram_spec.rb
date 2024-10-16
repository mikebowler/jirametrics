# frozen_string_literal: true

require './spec/spec_helper'

describe CycletimeHistogram do
  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:issue2) { load_issue 'SP-2', board: board }
  let(:issue10) { load_issue 'SP-10', board: board }
  let(:chart) { described_class.new(empty_config_block) }

  context 'histogram_data_for' do
    it 'handles no issues' do
      expect(chart.histogram_data_for issues: []).to be_empty
    end

    it 'handles a mix of issues' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2022-01-01', '2022-01-04'],
        [issue2, '2022-01-01', '2022-01-04'],
        [issue10, '2022-01-01', '2022-01-01T01:00:00']
      ]
      expect(chart.histogram_data_for issues: [issue1, issue2, issue10]).to eq({ 4 => 2, 1 => 1 })
    end
  end

  context 'data_set_for' do
    it 'handles no data' do
      expect(chart.data_set_for histogram_data: {}, label: 'foo', color: 'red').to eq({
        backgroundColor: 'red',
        borderRadius: 0,
        data: [],
        label: 'foo',
        type: 'bar'
      })
    end

    it 'handles simple data' do
      expect(chart.data_set_for histogram_data: { 4 => 2, 3 => 0 }, label: 'foo', color: 'red').to eq({
        backgroundColor: 'red',
        borderRadius: 0,
        data: [
          {
            title: '2 items completed in 4 days',
            x: 4,
            y: 2
          }
        ],
        label: 'foo',
        type: 'bar'
      })
    end
  end
end
