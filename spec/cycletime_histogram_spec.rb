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

  context 'stats_for' do
    it 'handles no issues' do
      expect(chart.stats_for histogram_data:{}).to eq({})
    end

    it 'calculates the average' do
      expect_average({ 4 => 2, 5 => 3, 10 => 0 }).to eq((4*2 + 5*3).to_f/(2 + 3))
      expect_average({ 10 => 1 }).to eq(10)
      expect_average({ 5 => 5 }).to eq(5)

      expect_average({ 1 => 0 }).to eq(0)
      expect_average({ 0 => 0 }).to eq(0)
    end

    it 'calculates the mode' do
      expect_mode({ 1 => 2, 2 => 5, 3 => 1 }).to eq(2)
      expect_mode({ 5 => 1 }).to eq(5)

      # Multi-modal distribution cases
      expect_mode({ 1 => 5, 2 => 1, 3 => 5 }).to eq([1, 3])
      expect_mode({ 5 => 1, 1 => 1 }).to eq([1, 5]) # make sure values come out sorted
    end

    it 'calculates min/max' do
      expect_minmax({ 4 => 2, 5 => 3, 10 => 0 }).to eq([4, 10])
      expect_minmax({ 15 => 1, 9 => 1, 8 => 0 }).to eq([8, 15])
      expect_minmax({ 7 => 2 }).to eq([7, 7])
    end

    it 'ignores percentiles if not requested' do
      stats = chart.stats_for histogram_data: { 1 => 1, 2 => 1}
      expect(stats[:percentiles]).to eq({})
    end

    it 'calculates percentiles' do
      expect_percentiles(
        { 1 => 1, 2 => 1, 3 => 1, 4 => 1, 5 => 1, 6 => 1, 7 => 1, 8 => 1, 9 => 1, 10 => 1}, [30, 50, 75, 99, 100] ).to eq(
        {30 => 3, 50 => 5, 75 => 8, 99 => 10, 100 => 10})

        expect_percentiles({ 3=>1, 6=>1, 7=>10, 15=> 1, 20 => 1}, [50, 75, 92]).to eq({50 => 7, 75 => 7, 92 => 15 })

        expect_percentiles({ 1=>1, 2=>1}, [101]).to eq({101 => nil})
        expect_percentiles({ 1=>1, 2=>1}, [0]).to eq({0 => 1})

    end

    def expect_percentiles(histogram_data, percentiles)
      stats = chart.stats_for histogram_data:histogram_data, percentiles:percentiles
      expect(stats[:percentiles])
    end

    def expect_mode(histogram_data)
      stats = chart.stats_for histogram_data:histogram_data
      expect(stats[:mode])
    end

    def expect_average(histogram_data)
      stats = chart.stats_for histogram_data:histogram_data
      expect(stats[:average])
    end

    def expect_minmax(histogram_data)
      stats = chart.stats_for histogram_data:histogram_data
      expect([stats[:min], stats[:max]])
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
