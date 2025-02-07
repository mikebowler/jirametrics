# frozen_string_literal: true

require './spec/spec_helper'

describe BoardMovementCalculator do
  let(:board) do
    sample_board.tap do |board|
      board.cycletime = default_cycletime_config
    end
  end
  let(:calculator) { described_class.new board: board, issues: load_complete_sample_issues(board: board) }

  context 'days_at_percentage_threshold_for_all_columns' do
    it 'at 100%' do
      actual = calculator.age_data_for percentage: 100
      expect(actual).to eq [0, 0, 0, 0]
    end

    it 'at 0%' do
      actual = calculator.age_data_for percentage: 0
      expect(actual).to eq [1, 1, 81, 81]
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
      expect(actual).to eq [180, 73, 1]
    end
  end
end
