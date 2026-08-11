# frozen_string_literal: true

require './spec/spec_helper'

describe TimeBasedHistogram do
  let(:chart) { described_class.new }

  describe '#percentiles' do
    it 'defaults to the median, the service level and the worst case' do
      expect(chart.percentiles).to eq [50, 85, 98]
    end

    it 'accepts a replacement list' do
      chart.percentiles [50, 90]
      expect(chart.percentiles).to eq [50, 90]
    end

    it 'accepts an empty list to switch the percentile columns off' do
      chart.percentiles []
      expect(chart.percentiles).to eq []
    end

    # These flow straight into the percentile arithmetic and into the stats table headers, so a
    # bad value produces a wrong chart rather than an error.
    it 'rejects values outside 0..100' do
      expect { chart.percentiles [50, 150] }.to raise_error(
        ArgumentError, /percentile 150 must be between 0 and 100/
      )
    end

    it 'rejects non-integers' do
      expect { chart.percentiles [85.5] }.to raise_error(
        ArgumentError, /percentile 85.5 must be an integer/
      )
    end

    it 'removes duplicates and sorts' do
      chart.percentiles [98, 50, 98]
      expect(chart.percentiles).to eq [50, 98]
    end
  end

  # The explanations used to be a hardcoded list of 50, 85 and 98 sitting under a table whose
  # columns follow the configuration, so the two drifted apart as soon as anyone changed it.
  describe '#percentile_explanation' do
    it 'calls out the median by name' do
      expect(chart.percentile_explanation(50)).to include 'Median'
    end

    it 'treats the upper middle as a service level expectation' do
      aggregate_failures do
        expect(chart.percentile_explanation(85)).to include 'service level expectations'
        expect(chart.percentile_explanation(90)).to include 'service level expectations'
      end
    end

    it 'treats the top of the range as the worst case' do
      aggregate_failures do
        expect(chart.percentile_explanation(95)).to include 'worst case'
        expect(chart.percentile_explanation(98)).to include 'worst case'
      end
    end

    # Nothing below the median is a planning number, and saying so is more useful than silence.
    it 'warns that anything below the median is not a planning number' do
      aggregate_failures do
        expect(chart.percentile_explanation(25)).to include 'takes longer'
        expect(chart.percentile_explanation(49)).to include 'takes longer'
      end
    end

    it 'has something to say about every value the setter accepts' do
      aggregate_failures do
        (0..100).each do |percentile|
          expect(chart.percentile_explanation(percentile)).not_to be_empty
        end
      end
    end
  end

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
      # 50th percentile of three equally-weighted values 1, 2, 3 is 2 - not whichever key came first.
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
