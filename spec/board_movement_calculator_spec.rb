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

  # Builds a done issue whose board movement is described entirely by explicit status changes, with the
  # start/stop times coming from a stubbed cycletime, so the per-issue methods (moves_backwards? and the
  # column skip rules) can each be isolated. Marking it Done lets it survive the constructor's
  # `issue.done?` filter for callers that go through the constructor.
  # Visible columns are: Ready(10001), In Progress(3), Review(10011), Done(10002).
  def issue_entering(statuses)
    start_status = board.possible_statuses.find_by_id(10_001)
    empty_issue(created: '2024-10-01', board: board, creation_status: start_status).tap do |issue|
      issue.changes.clear
      statuses.each do |name, id, time|
        add_mock_change(issue: issue, field: 'status', value: name, value_id: id, time: time)
      end
      # done? reads the current status (raw field), not the changes, so mark it Done to survive the
      # constructor's `issue.done?` filter. The cycletime stub still drives start/stop for the method.
      issue.status = board.possible_statuses.find_by_id(10_002)
    end
  end

  describe '#age_data_for' do
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

  describe '#moves_backwards?' do
    let(:calculator) { described_class.new board: board, issues: [], today: today }

    it 'is false when the issue never started' do
      # Review(col 2) then In Progress(col 1) would be backwards, but with no start time we cannot judge.
      issue = issue_entering([['Review', 10_011, '2024-10-02'], ['In Progress', 3, '2024-10-03']])
      board.cycletime = mock_cycletime_config stub_values: [[issue, nil, '2024-10-04']]
      expect(calculator.moves_backwards?(issue)).to be false
    end

    it 'is false when the columns only ever move forward' do
      issue = issue_entering(
        [['In Progress', 3, '2024-10-02'], ['Review', 10_011, '2024-10-03'], ['Done', 10_002, '2024-10-04']]
      )
      board.cycletime = mock_cycletime_config stub_values: [[issue, '2024-10-01', '2024-10-04']]
      expect(calculator.moves_backwards?(issue)).to be false
    end

    it 'is true when the issue moves to an earlier column' do
      # Review(col 2) back to In Progress(col 1).
      issue = issue_entering([['Review', 10_011, '2024-10-02'], ['In Progress', 3, '2024-10-03']])
      board.cycletime = mock_cycletime_config stub_values: [[issue, '2024-10-01', '2024-10-04']]
      expect(calculator.moves_backwards?(issue)).to be true
    end

    it 'ignores backwards movement that happened before the issue started' do
      # The Review -> In Progress dip is before the start; from the start it only goes In Progress -> Review.
      issue = issue_entering(
        [['Review', 10_011, '2024-10-02'], ['In Progress', 3, '2024-10-03'], ['Review', 10_011, '2024-10-06']]
      )
      board.cycletime = mock_cycletime_config stub_values: [[issue, '2024-10-05', '2024-10-07']]
      expect(calculator.moves_backwards?(issue)).to be false
    end

    it 'keeps scanning past a change that predates the start and still finds a later backwards step' do
      # In Progress predates the start (must be skipped, not treated as a stopping point); the real dip
      # from Review(col 2) back to In Progress(col 1) happens after the start.
      issue = issue_entering(
        [['In Progress', 3, '2024-10-02'], ['Review', 10_011, '2024-10-04'], ['In Progress', 3, '2024-10-05']]
      )
      board.cycletime = mock_cycletime_config stub_values: [[issue, '2024-10-03', '2024-10-06']]
      expect(calculator.moves_backwards?(issue)).to be true
    end

    it 'counts a change that lands exactly on the start time' do
      # Review enters right at the start; it still marks the issue's position, so the following move back
      # to In Progress reads as backwards.
      issue = issue_entering([['Review', 10_011, '2024-10-03'], ['In Progress', 3, '2024-10-04']])
      board.cycletime = mock_cycletime_config stub_values: [[issue, '2024-10-03', '2024-10-05']]
      expect(calculator.moves_backwards?(issue)).to be true
    end

    it 'still detects a step backwards across a status that is not on the board' do
      # Review(col 2), briefly off the board (FakeBacklog is a status with no visible column), then
      # In Progress(col 1). The gap must not hide the backwards step.
      issue = issue_entering(
        [['Review', 10_011, '2024-10-02'], ['FakeBacklog', 10_012, '2024-10-03'], ['In Progress', 3, '2024-10-04']]
      )
      board.cycletime = mock_cycletime_config stub_values: [[issue, '2024-10-01', '2024-10-05']]
      expect(calculator.moves_backwards?(issue)).to be true
    end
  end

  describe '#ages_of_issues_when_leaving_column' do
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

    it 'skips a done issue when we cannot tell it started' do
      issue = issue_entering([['In Progress', 3, '2024-10-05'], ['Done', 10_002, '2024-10-06']])
      board.cycletime = mock_cycletime_config stub_values: [[issue, nil, '2024-10-06']] # done, never started
      calculator = described_class.new board: board, issues: [issue], today: today
      expect(calculator.ages_of_issues_when_leaving_column(column_index: 1, today: today)).to eq []
    end

    it 'returns 0 when the issue left this column before it started' do
      issue = issue_entering(
        [['In Progress', 3, '2024-10-02'], ['Review', 10_011, '2024-10-03'], ['Done', 10_002, '2024-10-04']]
      )
      # Started (per the cycletime) only after it had already reached Review.
      board.cycletime = mock_cycletime_config stub_values: [[issue, '2024-10-05', '2024-10-06']]
      calculator = described_class.new board: board, issues: [issue], today: today
      expect(calculator.ages_of_issues_when_leaving_column(column_index: 1, today: today)).to eq [0]
    end

    it 'skips an issue that was already done by the time it reached this column' do
      issue = issue_entering([['In Progress', 3, '2024-10-10'], ['Done', 10_002, '2024-10-11']])
      board.cycletime = mock_cycletime_config stub_values: [[issue, '2024-10-01', '2024-10-05']] # done before 10-10
      calculator = described_class.new board: board, issues: [issue], today: today
      expect(calculator.ages_of_issues_when_leaving_column(column_index: 1, today: today)).to eq []
    end
  end

  describe '#stack_data' do
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

  describe '#forecasted_days_remaining_and_message' do
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
        [nil, 'This item is an outlier at 2 days in the "Ready" column. Most items on this board have ' \
          'left this column in 1 day or less, so we cannot forecast when it will be done.']
      )
    end
  end
end
