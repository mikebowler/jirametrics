# frozen_string_literal: true

require './spec/spec_helper'

describe BoardMovementCalculator do
  let(:today) { to_date('2024-10-31') }
  let(:board) do
    sample_board.tap do |board|
      board.cycletime = default_cycletime_config
    end
  end
  let(:issue1) do
    create_issue_from_aging_data board: board, ages_by_column: [1, 2, 3, 7], today: today.to_s, key: 'SP-1'
  end
  let(:issue2) do
    create_issue_from_aging_data board: board, ages_by_column: [4, 5, 6, 8], today: today.to_s, key: 'SP-2'
  end

  context 'age_data_for' do
    it 'has no issues' do
      calculator = described_class.new board: board, issues: [], today: today
      expect(calculator.age_data_for percentage: 100).to eq [0, 0, 0, 0]
    end

    it 'at 100%' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      expect(calculator.age_data_for percentage: 100).to eq [4, 8, 13, 20]
    end

    it 'at 0%' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      expect(calculator.age_data_for percentage: 0).to eq [1, 2, 4, 10]
    end
  end

  context 'ages_of_issues_when_leaving_column' do
    it 'handles no issues' do
      calculator = described_class.new board: board, issues: [], today: today
      actual = calculator.ages_of_issues_when_leaving_column column_index: 1, today: today
      expect(actual).to eq []
    end

    it 'has absolute values for first column' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      actual = calculator.ages_of_issues_when_leaving_column column_index: 0, today: today
      expect(actual).to eq [1, 4]
    end

    it 'accumulates for second column' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      actual = calculator.ages_of_issues_when_leaving_column column_index: 1, today: today
      expect(actual).to eq [2, 8]
    end

    it 'picks up current age if the issue is still in the specified column' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      actual = calculator.ages_of_issues_when_leaving_column column_index: 2, today: today
      expect(actual).to eq [4, 13]
    end

    it 'handles the case where the issue completes on column transition', :focus do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, issue1.created, issue1.first_time_in_status('Done')],  # should age out normally from review
        [issue2, issue2.created, issue2.first_time_in_status('Review')] # should complete in Review
      ]
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      # puts "column 1"
      # actual = calculator.ages_of_issues_when_leaving_column column_index: 1, today: today
      # expect(actual).to eq [2, 8]

      puts "column 2"
      actual = calculator.ages_of_issues_when_leaving_column column_index: 2, today: today
      expect(actual).to eq [4]
    end
  end

  context 'ensure_numbers_always_goes_up' do
    let(:calculator) { described_class.new board: board, issues: [], today: today }

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
      calculator = described_class.new board: board, issues: [], today: today
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
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      expect(calculator.forecasted_days_remaining_and_message issue: issue1, today: today).to eq [0, '']
    end
  end
end
