# frozen_string_literal: true

require './spec/spec_helper'

describe ChartBase do
  let(:chart_base) { described_class.new }

  context 'label_days' do
    it 'is singular for one' do
      expect(chart_base.label_days(1)).to eq '1 day'
    end

    it 'is plural for five' do
      expect(chart_base.label_days(5)).to eq '5 days'
    end
  end

  context 'label_issues' do
    it 'is singular for one' do
      expect(chart_base.label_issues(1)).to eq '1 issue'
    end

    it 'is plural for five' do
      expect(chart_base.label_issues(5)).to eq '5 issues'
    end
  end

  context 'daily_chart_dataset' do
    let(:issue1) { load_issue('SP-1') }

    it 'handles the simple positive case' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = chart_base.daily_chart_dataset(
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

    it 'handles the positive case with a block' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = chart_base.daily_chart_dataset(
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

    it 'handles the simple negative case' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = chart_base.daily_chart_dataset(
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
    let(:aging_chart) do
      # Not all charts have a board_id. Use one that does.
      AgingWorkInProgressChart.new(empty_config_block)
    end

    it 'raises exception if board cannot be determined' do
      aging_chart.all_boards = {}
      expect { aging_chart.current_board }.to raise_error 'Couldn\'t find any board configurations. Ensure one is set'
    end

    it 'returns correct columns when board id set' do
      board1 = Board.new raw: raw_board
      aging_chart.board_id = 1
      aging_chart.all_boards = { 1 => board1 }
      expect(aging_chart.current_board).to be board1
    end

    it 'returns correct columns when board id not set but only one board in use' do
      board1 = Board.new raw: raw_board
      aging_chart.all_boards = { 1 => board1 }
      expect(aging_chart.current_board).to be board1
    end

    it 'raises exception when board id not set and multiple boards in use' do
      board1 = Board.new raw: raw_board
      board2 = Board.new raw: raw_board
      aging_chart.all_boards = { 1 => board1, 2 => board2 }
      expect { aging_chart.current_board }.to raise_error(
        'Must set board_id so we know which to use. Multiple boards found: [1, 2]'
      )
    end
  end

  context 'completed_issues_in_range' do
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue('SP-1', board: board) }

    it 'returns empty when no issues match' do
      chart_base.issues = [issue1]
      board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, nil]]
      expect(chart_base.completed_issues_in_range include_unstarted: true).to be_empty
    end

    it 'returns empty when one issue finished but outside the range' do
      chart_base.issues = [issue1]
      chart_base.date_range = Date.parse('2022-01-01')..Date.parse('2022-02-02')
      board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, '2000-01-02']]
      expect(chart_base.completed_issues_in_range include_unstarted: true).to be_empty
    end

    it 'returns one when issue finished' do
      chart_base.issues = [issue1]
      chart_base.date_range = Date.parse('2022-01-01')..Date.parse('2022-02-02')
      board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, '2022-01-02']]
      expect(chart_base.completed_issues_in_range include_unstarted: true).to eq [issue1]
    end
  end

  context 'holidays' do
    it 'handles Tues-Thu in the same week' do
      chart_base.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-03')
      chart_base.holiday_dates = []
      expect(chart_base.holidays).to eq []
    end

    it 'handles Tues-Tues in the next week' do
      chart_base.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-08')
      chart_base.holiday_dates = []
      expect(chart_base.holidays).to eq [Date.parse('2022-02-05')..Date.parse('2022-02-06')]
    end

    it 'handles a three day weekend' do
      chart_base.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-08')
      chart_base.holiday_dates = [Date.parse('2022-02-04')]
      expect(chart_base.holidays).to eq [Date.parse('2022-02-04')..Date.parse('2022-02-06')]
    end
  end

  context 'format_integer' do
    it 'formats for three digits or less' do
      expect(chart_base.format_integer 5).to eq '5'
      expect(chart_base.format_integer 500).to eq '500'
    end

    it 'formats for 4-6 digits' do
      expect(chart_base.format_integer 1000).to eq '1,000'
      expect(chart_base.format_integer 999_999).to eq '999,999'
    end

    it 'formats for 7-9 digits' do
      expect(chart_base.format_integer 1_000_000).to eq '1,000,000'
      expect(chart_base.format_integer 999_999_999).to eq '999,999,999'
    end
  end

  context 'format_status' do
    let(:board) do
      load_complete_sample_board.tap do |board|
        today = Date.parse('2021-12-17')
        block = lambda do |_|
          start_at first_status_change_after_created
          stop_at last_resolution
        end

        board.cycletime = CycleTimeConfig.new parent_config: nil, label: 'default', block: block, today: today
      end
    end

    it 'makes text red when status not found' do
      expect(chart_base.format_status 'Digging', board: board).to eq "<span style='color: red'>Digging</span>"
    end

    it 'handles todo statuses' do
      expect(chart_base.format_status 'Backlog', board: board).to eq(
        "<span title='Category: To Do'><div class='color_block' " \
          "style='background: var(--status-category-todo-color);'></div> Backlog</span>" \
          "<span title='Not visible: The status \"Backlog\" is not mapped to any column and " \
          "will not be visible' style='font-size: 0.8em;'> 👀</span>"
      )
    end

    it 'handles in progress statuses' do
      expect(chart_base.format_status 'Review', board: board).to eq(
        "<span title='Category: In Progress'><div class='color_block' " \
          "style='background: var(--status-category-inprogress-color);'></div> Review</span>"
      )
    end

    it 'handles done statuses' do
      expect(chart_base.format_status 'Done', board: board).to eq(
        "<span title='Category: Done'><div class='color_block' " \
          "style='background: var(--status-category-done-color);'></div> Done</span>"
      )
    end

    it 'handles unknown statuses' do
      expect(chart_base.format_status 'unknown', board: board).to eq "<span style='color: red'>unknown</span>"
    end
  end

  context 'link_to_issue' do
    let(:issue1) { load_issue('SP-1') }

    it 'handles easy case' do
      expect(chart_base.link_to_issue issue1).to eq(
        "<a href='https://improvingflow.atlassian.net/browse/SP-1' class='issue_key'>SP-1</a>"
      )
    end

    it 'handles style parameter' do
      expect(chart_base.link_to_issue issue1, style: 'color: gray').to eq(
        "<a href='https://improvingflow.atlassian.net/browse/SP-1' class='issue_key' style='color: gray'>SP-1</a>"
      )
    end
  end

  it 'returns black for an unknown status category' do
    expect(chart_base.status_category_color(Status.new)).to eq 'black'
  end

  it 'returns reasonable random color' do
    # Since it's random, all we can verify is the format.
    expect(chart_base.random_color).to match(/^#[0-9a-f]{6}$/)
  end
end
