# frozen_string_literal: true

require './spec/spec_helper'

describe ChartBase do
  let(:subject) { ChartBase.new }

  context 'label_days' do
    it 'should be singular for one' do
      expect(subject.label_days(1)).to eq '1 day'
    end

    it 'should be singular for one' do
      expect(subject.label_days(5)).to eq '5 days'
    end
  end

  context 'label_issues' do
    it 'should be singular for one' do
      expect(subject.label_issues(1)).to eq '1 issue'
    end

    it 'should be singular for one' do
      expect(subject.label_issues(5)).to eq '5 issues'
    end
  end

  context 'daily_chart_dataset' do
    let(:issue1) { load_issue('SP-1') }

    it 'should hande the simple positive case' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = subject.daily_chart_dataset(
        date_issues_list: date_issues_list, color: 'red', label: 'MyChart', positive: true
      )

      expect(dataset).to eq({
        type: 'bar',
        label: 'MyChart',
        data: [
          {
            title: ['MyChart (1 issue)', 'SP-1 : Create new draft event'],
            x: Date.parse('2021-10-10'),
            y: 1
          }
        ],
        backgroundColor: 'red',
        borderRadius: 0
      })
    end

    it 'should hande the positive case with a block' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = subject.daily_chart_dataset(
        date_issues_list: date_issues_list, color: 'red', label: 'MyChart', positive: true
      ) { |_date, _issue| '(dynamic content!)' }

      expect(dataset).to eq({
        type: 'bar',
        label: 'MyChart',
        data: [
          {
            title: ['MyChart (1 issue)', 'SP-1 : Create new draft event (dynamic content!)'],
            x: Date.parse('2021-10-10'),
            y: 1
          }
        ],
        backgroundColor: 'red',
        borderRadius: 0
      })
    end

    it 'should hande the simple negative case' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = subject.daily_chart_dataset(
        date_issues_list: date_issues_list, color: 'red', label: 'MyChart', positive: false
      )

      expect(dataset).to eq({
        type: 'bar',
        label: 'MyChart',
        data: [
          {
            title: ['MyChart (1 issue)', 'SP-1 : Create new draft event'],
            x: Date.parse('2021-10-10'),
            y: -1
          }
        ],
        backgroundColor: 'red',
        borderRadius: 5
      })
    end
  end

  context 'board_columns' do
    let(:raw_board) { { 'type' => 'scrum', 'columnConfig' => { 'columns' => [] } } }

    it 'should raise exception if board cannot be determined' do
      subject.all_boards = {}
      expect { subject.current_board }.to raise_error 'Couldn\'t find any board configurations. Ensure one is set'
    end

    it 'should return correct columns when board id set' do
      board1 = Board.new raw: raw_board
      subject.board_id = 1
      subject.all_boards = { 1 => board1 }
      expect(subject.current_board).to be board1
    end

    it 'should return correct columns when board id not set but only one board in use' do
      board1 = Board.new raw: raw_board
      subject.all_boards = { 1 => board1 }
      expect(subject.current_board).to be board1
    end

    it 'should raise exception when board id not set and multiple boards in use' do
      board1 = Board.new raw: raw_board
      board2 = Board.new raw: raw_board
      subject.all_boards = { 1 => board1, 2 => board2 }
      expect { subject.current_board }.to raise_error(
        'Must set board_id so we know which to use. Multiple boards found: [1, 2]'
      )
    end
  end

  context 'completed_issues_in_range' do
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue('SP-1', board: board) }

    it 'should return empty when no issues match' do
      subject.issues = [issue1]
      board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, nil]]
      expect(subject.completed_issues_in_range include_unstarted: true).to be_empty
    end

    it 'should return empty when one issue finished but outside the range' do
      subject.issues = [issue1]
      subject.date_range = Date.parse('2022-01-01')..Date.parse('2022-02-02')
      board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, '2000-01-02']]
      expect(subject.completed_issues_in_range include_unstarted: true).to be_empty
    end

    it 'should return one when issue finished' do
      subject.issues = [issue1]
      subject.date_range = Date.parse('2022-01-01')..Date.parse('2022-02-02')
      board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, '2022-01-02']]
      expect(subject.completed_issues_in_range include_unstarted: true).to eq [issue1]
    end
  end

  context 'holidays' do
    it 'should handle Tues-Thu in the same week' do
      subject.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-03')
      subject.holiday_dates = []
      expect(subject.holidays).to eq []
    end

    it 'should handle Tues-Tues in the next week' do
      subject.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-08')
      subject.holiday_dates = []
      expect(subject.holidays).to eq [Date.parse('2022-02-05')..Date.parse('2022-02-06')]
    end

    it 'should handle a three day weekend' do
      subject.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-08')
      subject.holiday_dates = [Date.parse('2022-02-04')]
      expect(subject.holidays).to eq [Date.parse('2022-02-04')..Date.parse('2022-02-06')]
    end
  end

  context 'format_integer' do
    it 'should format for three digits or less' do
      expect(subject.format_integer 5).to eq '5'
      expect(subject.format_integer 500).to eq '500'
    end

    it 'should format for 4-6 digits' do
      expect(subject.format_integer 1000).to eq '1,000'
      expect(subject.format_integer 999_999).to eq '999,999'
    end

    it 'should format for 7-9 digits' do
      expect(subject.format_integer 1_000_000).to eq '1,000,000'
      expect(subject.format_integer 999_999_999).to eq '999,999,999'
    end
  end
end
