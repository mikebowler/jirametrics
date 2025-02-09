# frozen_string_literal: true

require './spec/spec_helper'

describe BoardMovementCalculator do
  let(:board) do
    sample_board.tap do |board|
      board.cycletime = default_cycletime_config
    end
  end
  let(:calculator) { described_class.new board: board, issues: load_complete_sample_issues(board: board) }

  context 'age_data_for' do
    it 'at 100%' do
      actual = calculator.age_data_for percentage: 100
      expect(actual).to eq [180, 180, 180, 0]
    end

    it 'at 0%' do
      actual = calculator.age_data_for percentage: 0
      expect(actual).to eq [1, 81, 81, 0]
    end
  end

  context 'ages_of_issues_that_crossed_column_boundary' do
    it 'handles no issues' do
      calculator = described_class.new board: board, issues: []
      actual = calculator.ages_of_issues_that_crossed_column_boundary status_ids: [10_002, 10_011]
      expect(actual).to eq []
    end

    it 'handles no status ids' do
      actual = calculator.ages_of_issues_that_crossed_column_boundary status_ids: []
      expect(actual).to eq []
    end

    it 'handles happy path' do
      actual = calculator.ages_of_issues_that_crossed_column_boundary status_ids: [10_002, 10_011, 3]
      expect(actual).to eq [1, 73, 180]
    end
  end

  context 'ensure_numbers_always_goes_up' do
    it 'retains order of already correct data' do
      expect(calculator.ensure_numbers_always_goes_up [1, 2, 3]).to eql [1, 2, 3]
    end

    it 'retains numbers that go down' do
      expect(calculator.ensure_numbers_always_goes_up [1, 2, 1]).to eql [1, 2, 2]
    end

    it 'allows zeros at the end' do
      expect(calculator.ensure_numbers_always_goes_up [1, 2, 0]).to eql [1, 2, 0]
    end

    it 'handles all zeros' do
      expect(calculator.ensure_numbers_always_goes_up [0, 0, 0]).to eql [0, 0, 0]
    end
  end

  context 'stack_data', :focus do
    it 'stacks' do
      inputs = [
        [50, [0, 0, 2, 3, 3]],
        [85, [0, 0, 11, 12, 14]],
        [98, [0, 0, 34, 36, 36]]
      ]
      expect(calculator.stack_data inputs).to eq [
        [50, [0, 0, 2, 3, 3]],
        [85, [0, 0, 9, 9, 11]],
        [98, [0, 0, 25, 27, 25]]
      ]
    end
  end
end
