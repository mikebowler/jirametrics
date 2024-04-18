# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/trend_line_calculator'

describe TrendLineCalculator do
  context 'valid?' do
    it 'no points' do
      expect(described_class.new []).not_to be_valid
    end

    it 'one point' do
      expect(described_class.new [[1, 2]]).not_to be_valid
    end

    it 'Two points' do
      expect(described_class.new [[1, 2], [3, 4]]).to be_valid
    end
  end

  context 'calc_y' do
    it 'calculates for two simple points' do
      calculator = described_class.new [[3, 3], [2, 2]]
      expect(calculator.calc_y x: 4).to eq 4.0
      expect(calculator.calc_y x: 1).to eq 1.0
    end

    it 'calculates for a perfect horizontal trend' do
      calculator = described_class.new [[1, 2], [2, 2]]
      expect(calculator.calc_y x: 4).to eq 2.0
    end
  end

  context 'line_crosses_at' do
    it 'calculates for two simple points' do
      calculator = described_class.new [[4, 3], [3, 2]]
      expect(calculator).not_to be_horizontal
      expect(calculator.line_crosses_at y: 0).to eq 1.0
    end

    it 'calculates for a perfect horizontal trend' do
      calculator = described_class.new [[1, 2], [2, 2]]
      expect(calculator).to be_horizontal
      expect { calculator.line_crosses_at y: 0 }.to raise_error(
        'line will never cross 0. Trend is perfectly horizontal'
      )
    end
  end

  context 'chart_datapoints' do
    it 'returns return empty array when trend cant be calculated' do
      calculator = described_class.new []
      expect(calculator.chart_datapoints range: 3..4, max_y: 100).to be_empty
    end

    it 'returns a pair of points for a perfect horizontal' do
      calculator = described_class.new [[1, 2], [2, 2]]
      expect(calculator.chart_datapoints range: 3..4, max_y: 100).to eq([
        { x: 3, y: 2 },
        { x: 4, y: 2 }
      ])
    end

    it 'stops at zero for a descending line' do
      calculator = described_class.new [[1, 2], [2, 1]]
      expect(calculator.chart_datapoints range: 1..4, max_y: 100).to eq([
        { x: 1, y: 2 },
        { x: 3, y: 0 }
      ])
    end

    it 'starts at zero for a ascending line' do
      calculator = described_class.new [[12, 3], [13, 4]]
      expect(calculator.chart_datapoints range: 0..15, max_y: 100).to eq([
        { x: 9, y: 0 },
        { x: 15, y: 6 }
      ])
    end

    it 'does not exceed max_y for an ascending line' do
      calculator = described_class.new [[12, 3], [13, 4]]
      expect(calculator.chart_datapoints range: 0..15, max_y: 5).to eq([
        { x: 9, y: 0 },
        { x: 14, y: 5 }
      ])
    end

    it 'does not exceed max_y for a descending line' do
      calculator = described_class.new [[12, 9], [13, 8]]
      expect(calculator.chart_datapoints range: 0..15, max_y: 10).to eq([
        { x: 11, y: 10 },
        { x: 15, y: 6 }
      ])
    end

    it 'handles a vertical line' do
      calculator = described_class.new [[12, 9], [12, 8]]
      expect(calculator.chart_datapoints range: 0..15, min_y: 2, max_y: 10).to eq([])
    end

    it 'raises error if max_y is nil' do
      calculator = described_class.new [[12, 9], [12, 8]]
      expect { calculator.chart_datapoints range: 0..15, max_y: nil }.to raise_error 'max_y is nil'
    end
  end
end
