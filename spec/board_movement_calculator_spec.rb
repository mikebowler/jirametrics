# frozen_string_literal: true

require './spec/spec_helper'

describe BoardMovementCalculator do
  let(:today) { to_date('2024-10-31') }
  let(:board) do
    sample_board.tap do |board|
      block = lambda do |_|
        start_at first_time_in_status 10_001
        stop_at first_time_in_status 10_002
      end
      board.cycletime = CycleTimeConfig.new(
        possible_statuses: nil, label: 'test', file_system: nil, today: today, block: block,
        settings: load_settings
      )
    end
  end

  # Visible columns are: "Ready(10001)", "In Progress(3)", "Review(10011)", "Done(10002)"
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
      expect(calculator.age_data_for percentage: 100).to eq [4, 8, 13, 0]
    end

    it 'at 100% with one issue' do
      calculator = described_class.new board: board, issues: [issue1], today: today
      expect(calculator.age_data_for percentage: 100).to eq [1, 2, 4, 0]
    end

    it 'at 0%' do # TODO: 0% should probably return all zeros
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      expect(calculator.age_data_for percentage: 0).to eq [1, 2, 4, 0]
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

    it 'handles the case where the issue completes on column transition' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, issue1.created, issue1.first_time_in_status('Done')],  # should age out normally from review
        [issue2, issue2.created, issue2.first_time_in_status('Review')] # should complete in Review
      ]
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      # puts "column 1"
      # actual = calculator.ages_of_issues_when_leaving_column column_index: 1, today: today
      # expect(actual).to eq [2, 8]

      # puts "column 2"
      actual = calculator.ages_of_issues_when_leaving_column column_index: 2, today: today
      expect(actual).to eq [4]
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

  context 'forecasted_days_remaining_and_message' do
    # The 85% ages across this table with issue1 and issue2 is 1, 2, 4

    it 'is already done' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      expect(calculator.forecasted_days_remaining_and_message issue: issue1, today: today).to eq [nil, 'Already done']
    end

    it 'has no historical data' do
      calculator = described_class.new board: board, issues: [], today: today
      new_issue = create_issue_from_aging_data board: board, ages_by_column: [1], today: today.to_s, key: 'SP-100'
      expect(calculator.forecasted_days_remaining_and_message issue: new_issue, today: today).to eq(
        [nil, 'There is no historical data for this board. No forecast can be made.']
      )
    end

    it 'is on the first day in the ready column and should take four days total to get across' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      new_issue = create_issue_from_aging_data board: board, ages_by_column: [1], today: today.to_s, key: 'SP-100'
      expect(calculator.forecasted_days_remaining_and_message issue: new_issue, today: today).to eq [3, nil]
    end

    it 'is already an outlier in the first column' do
      calculator = described_class.new board: board, issues: [issue1, issue2], today: today
      new_issue = create_issue_from_aging_data board: board, ages_by_column: [2], today: today.to_s, key: 'SP-100'
      expect(calculator.forecasted_days_remaining_and_message issue: new_issue, today: today).to eq(
        [nil, 'This item is an outlier at 2 days in the "Ready" column. Most items on this board have left this column ' \
          'in 1 day or less, so we cannot forecast when it will be done.']
      )
    end
  end
end
