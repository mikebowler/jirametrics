# frozen_string_literal: true

require './spec/spec_helper'

describe TimeBasedHistogram do
  let(:chart) { described_class.new }

  describe '#stats_for' do
    it 'handles no issues' do
      expect(chart.stats_for histogram_data: {}, percentiles: []).to eq({})
    end

    it 'calculates the average' do
      expect_average({ 4 => 2, 5 => 3, 10 => 0 }).to eq(((4 * 2) + (5 * 3)).to_f / (2 + 3))
      expect_average({ 10 => 1 }).to eq(10)
      expect_average({ 5 => 5 }).to eq(5)

      expect_average({ 1 => 0 }).to eq(0)
      expect_average({ 0 => 0 }).to eq(0)
    end

    it 'calculates the mode' do
      expect_mode({ 1 => 2, 2 => 5, 3 => 1 }).to eq([2])
      expect_mode({ 5 => 1 }).to eq([5])

      # Multi-modal distribution cases
      expect_mode({ 1 => 5, 2 => 1, 3 => 5 }).to eq([1, 3])
      expect_mode({ 5 => 1, 1 => 1 }).to eq([1, 5]) # make sure values come out sorted
    end

    it 'calculates min/max' do
      expect_minmax({ 4 => 2, 5 => 3, 10 => 0 }).to eq([4, 10])
      expect_minmax({ 15 => 1, 9 => 1, 8 => 0 }).to eq([8, 15])
      expect_minmax({ 5 => 1, 9 => 1, 1 => 0, 2 => 0 }).to eq([1, 9])
      expect_minmax({ 7 => 2 }).to eq([7, 7])
    end

    it 'sorts by value before computing percentiles, whatever order the keys arrive in' do
      # Keys given high-to-low: percentiles must still accumulate against ascending values, so the
      # 50th percentile of three equally-weighted values 1, 2, 3 is 2 — not whichever key came first.
      expect_percentiles({ 3 => 1, 1 => 1, 2 => 1 }, [50]).to eq({ 50 => 2 })
    end

    it 'ignores percentiles if not requested' do
      stats = chart.stats_for histogram_data: { 1 => 1, 2 => 1 }, percentiles: []
      expect(stats[:percentiles]).to eq({})
    end

    it 'calculates percentiles' do
      expect_percentiles(
        { 1 => 1, 2 => 1, 3 => 1, 4 => 1, 5 => 1, 6 => 1, 7 => 1, 8 => 1, 9 => 1, 10 => 1 }, [30, 50, 75, 99, 100]
      ).to eq(
        { 30 => 3, 50 => 5, 75 => 8, 99 => 10, 100 => 10 }
      )

      expect_percentiles(
        { 3 => 1, 6 => 1, 7 => 10, 15 => 1, 20 => 1 }, [50, 75, 92]
      ).to eq(
        { 50 => 7, 75 => 7, 92 => 15 }
      )

      expect_percentiles(
        { 1 => 1, 2 => 1 }, [101]
      ).to eq(
        { 101 => nil }
      )
      expect_percentiles(
        { 1 => 1, 2 => 1 }, [0]
      ).to eq(
        { 0 => 1 }
      )
    end

    def expect_percentiles(histogram_data, percentiles)
      stats = chart.stats_for histogram_data: histogram_data, percentiles: percentiles
      expect(stats[:percentiles])
    end

    def expect_mode(histogram_data)
      stats = chart.stats_for histogram_data: histogram_data, percentiles: []
      expect(stats[:mode])
    end

    def expect_average(histogram_data)
      stats = chart.stats_for histogram_data: histogram_data, percentiles: []
      expect(stats[:average])
    end

    def expect_minmax(histogram_data)
      stats = chart.stats_for histogram_data: histogram_data, percentiles: []
      expect([stats[:min], stats[:max]])
    end
  end
end
