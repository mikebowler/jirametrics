# frozen_string_literal: true

require './spec/spec_helper'

describe CycletimeHistogram do
  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:issue2) { load_issue 'SP-2', board: board }
  let(:issue10) { load_issue 'SP-10', board: board }
  let(:chart) { described_class.new(empty_config_block) }

  describe '#cycletime_unit' do
    it 'accepts :days (the only supported unit)' do
      expect { chart.cycletime_unit :days }.not_to raise_error
    end

    it 'raises NotImplementedError for any other unit' do
      expect { chart.cycletime_unit :hours }.to raise_error(
        NotImplementedError, /CycletimeHistogram only supports :days/
      )
    end
  end

  describe '#histogram_data_for' do
    it 'handles no issues' do
      expect(chart.histogram_data_for items: []).to be_empty
    end

    it 'handles a mix of issues' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2022-01-01', '2022-01-04'],
        [issue2, '2022-01-01', '2022-01-04'],
        [issue10, '2022-01-01', '2022-01-01T01:00:00']
      ]
      expect(chart.histogram_data_for items: [issue1, issue2, issue10]).to eq({ 4 => [issue1, issue2], 1 => [issue10] })
    end
  end

  describe '#data_set_for' do
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
      board.cycletime = default_cycletime_config
      result = chart.data_set_for histogram_data: { 4 => [issue1, issue2], 3 => [] }, label: 'foo', color: 'red'
      expect(result).to eq({
        backgroundColor: 'red',
        borderRadius: 0,
        data: [
          {
            title: [
              '2 items completed in 4 days',
              "#{issue1.key} : #{issue1.summary}",
              "#{issue2.key} : #{issue2.summary}"
            ],
            x: 4,
            y: 2
          }
        ],
        label: 'foo',
        type: 'bar'
      })
    end

    it 'appends issue_hint to each issue line when set' do
      board.cycletime = default_cycletime_config
      chart.issue_hints = { issue1 => '(hint for issue1)' }
      result = chart.data_set_for histogram_data: { 4 => [issue1] }, label: 'foo', color: 'red'
      expect(result[:data].first[:title][1]).to eq "#{issue1.key} : #{issue1.summary} (hint for issue1)"
    end
  end

  describe '#sort_items' do
    it 'sorts by key_as_i' do
      expect(chart.sort_items([issue10, issue1, issue2])).to eq([issue1, issue2, issue10])
    end
  end

  describe '#label_for_item' do
    it 'formats issue key and summary without hint' do
      expect(chart.label_for_item(issue1, hint: nil)).to eq("#{issue1.key} : #{issue1.summary}")
    end

    it 'appends hint when provided' do
      expect(chart.label_for_item(issue1, hint: '(my hint)')).to eq("#{issue1.key} : #{issue1.summary} (my hint)")
    end
  end
end
