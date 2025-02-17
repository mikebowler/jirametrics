# frozen_string_literal: true

require './spec/spec_helper'

describe BoardMovementCalculator do
  let(:today) { '2024-10-31' }
  let(:board) do
    sample_board.tap do |board|
      board.cycletime = default_cycletime_config
    end
  end
  let(:issue1) { create_issue_from_aging_data board: board, ages_by_column: [1, 2, 3], today: today, key: 'SP-1' }
  let(:issue2) { create_issue_from_aging_data board: board, ages_by_column: [4, 5, 6], today: today, key: 'SP-2' }

  context 'age_data_for' do
    it 'has no issues' do
      calculator = described_class.new board: board, issues: [], today: to_date(today)
      expect(calculator.age_data_for percentage: 100).to eq [0, 0, 0, 0]
    end

    it 'at 100%' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: to_date(today)
      expect(calculator.age_data_for percentage: 100).to eq [4, 8, 13, 13]
    end

    it 'at 0%' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: to_date(today)
      expect(calculator.age_data_for percentage: 0).to eq [1, 2, 4, 4]
    end
  end

  context 'ages_of_issues_when_leaving_column' do
    it 'handles no issues' do
      calculator = described_class.new board: board, issues: [], today: to_date(today)
      actual = calculator.ages_of_issues_when_leaving_column column_index: 1, today: to_date(today)
      expect(actual).to eq []
    end

    it 'has absolute values for first column' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: to_date(today)
      actual = calculator.ages_of_issues_when_leaving_column column_index: 0, today: to_date(today)
      expect(actual).to eq [1, 4]
    end

    it 'accumulates for second column' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: to_date(today)
      actual = calculator.ages_of_issues_when_leaving_column column_index: 1, today: to_date(today)
      expect(actual).to eq [2, 8]
    end

    it 'picks up current age if the issue is still in the specified column' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: to_date(today)
      actual = calculator.ages_of_issues_when_leaving_column column_index: 2, today: to_date(today)
      expect(actual).to eq [4, 13]
    end
  end

  context 'ensure_numbers_always_goes_up' do
    let(:calculator) { described_class.new board: board, issues: [], today: to_date(today) }

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

  context 'stack_data' do
    it 'stacks' do
      calculator = described_class.new board: board, issues: [], today: to_date(today)
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

  xcontext 'forecasted_days_remaining_and_message' do
    it "isn't started" do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: to_date(today)
      expect(calculator.forecasted_days_remaining_and_message issue: issue1, today: to_date(today)).to eq [0, '']
    end
  end
end
