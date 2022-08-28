# frozen_string_literal: true

require './spec/spec_helper'
require './lib/trend_line_calculator'

describe TrendLineCalculator do
  context 'valid?' do
    it 'no points' do
      expect(TrendLineCalculator.new []).not_to be_valid
    end

    it 'one point' do
      expect(TrendLineCalculator.new [[1, 2]]).not_to be_valid
    end

    it 'Two points' do
      expect(TrendLineCalculator.new [[1, 2], [3, 4]]).to be_valid
    end
  end

  context 'calc_y' do
    it 'calculates for two simple points' do
      calculator = TrendLineCalculator.new [[3, 3], [2, 2]]
      expect(calculator.calc_y x: 4).to eq 4.0
      expect(calculator.calc_y x: 1).to eq 1.0
    end

    it 'calculates for a perfect horizontal trend' do
      calculator = TrendLineCalculator.new [[1, 2], [2, 2]]
      expect(calculator.calc_y x: 4).to eq 2.0
    end
  end

  context 'calc_x_where_y_is_zero' do
    it 'calculates for two simple points' do
      calculator = TrendLineCalculator.new [[4, 3], [3, 2]]
      expect(calculator.horizontal?).to be_falsey
      expect(calculator.calc_x_where_y_is_zero).to eq 1.0
    end

    it 'calculates for a perfect horizontal trend' do
      calculator = TrendLineCalculator.new [[1, 2], [2, 2]]
      expect(calculator.horizontal?).to be_truthy
      expect { calculator.calc_x_where_y_is_zero }.to raise_error('y will never be zero. Trend is perfectly horizontal')
    end
  end

  context 'chart_datapoints' do
    it 'should return empty array when trend cant be calculated' do
      calculator = TrendLineCalculator.new []
      expect(calculator.chart_datapoints range: 3..4).to be_empty
    end

    it 'should return a pair of points for a perfect horizontal' do
      calculator = TrendLineCalculator.new [[1, 2], [2, 2]]
      expect(calculator.chart_datapoints range: 3..4).to eq([
        { x: 3, y: 2 },
        { x: 4, y: 2 }
      ])
    end

    it 'should stop at zero for a descending line' do
      calculator = TrendLineCalculator.new [[1, 2], [2, 1]]
      expect(calculator.chart_datapoints range: 1..4).to eq([
        { x: 1, y: 2 },
        { x: 3, y: 0 }
      ])
    end

    it 'should start at zero for a ascending line' do
      calculator = TrendLineCalculator.new [[12, 3], [13, 4]]
      expect(calculator.chart_datapoints range: 0..15).to eq([
        { x: 9, y: 0 },
        { x: 15, y: 6 }
      ])
    end
  end

end
