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
      board1 = Board.new raw: raw_board, possible_statuses: StatusCollection.new
      aging_chart.board_id = 1
      aging_chart.all_boards = { 1 => board1 }
      expect(aging_chart.current_board).to be board1
    end

    it 'returns correct columns when board id not set but only one board in use' do
      board1 = Board.new raw: raw_board, possible_statuses: StatusCollection.new
      aging_chart.all_boards = { 1 => board1 }
      expect(aging_chart.current_board).to be board1
    end

    it 'raises exception when board id not set and multiple boards in use' do
      board1 = Board.new raw: raw_board, possible_statuses: StatusCollection.new
      board2 = Board.new raw: raw_board, possible_statuses: StatusCollection.new
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

  context 'stagger_label_positions' do
    before { chart_base.date_range = Date.parse('2022-01-01')..Date.parse('2022-12-31') }

    it 'returns empty for no datetimes' do
      expect(chart_base.stagger_label_positions([])).to eq []
    end

    it 'returns ["5%"] for a single datetime' do
      expect(chart_base.stagger_label_positions(['2022-06-01T00:00:00+00:00'])).to eq ['5%']
    end

    it 'returns ["5%", "5%"] for datetimes far apart' do
      expect(
        chart_base.stagger_label_positions(['2022-01-01T00:00:00+00:00', '2022-12-01T00:00:00+00:00'])
      ).to eq ['5%', '5%']
    end

    it 'returns ["5%", "25%"] for datetimes close together' do
      expect(
        chart_base.stagger_label_positions(['2022-06-01T00:00:00+00:00', '2022-06-03T00:00:00+00:00'])
      ).to eq ['5%', '25%']
    end

    it 'returns ["5%", "25%", "45%"] for three datetimes all close together' do
      expect(chart_base.stagger_label_positions([
        '2022-06-01T00:00:00+00:00', '2022-06-02T00:00:00+00:00', '2022-06-03T00:00:00+00:00'
      ])).to eq ['5%', '25%', '45%']
    end

    it 'resets slot after a large gap' do
      expect(chart_base.stagger_label_positions([
        '2022-01-01T00:00:00+00:00', '2022-01-02T00:00:00+00:00', '2022-12-01T00:00:00+00:00'
      ])).to eq ['5%', '25%', '5%']
    end

    it 'wraps around after exhausting all positions' do
      datetimes = (1..5).map { |d| "2022-06-0#{d}T00:00:00+00:00" }
      expect(chart_base.stagger_label_positions(datetimes)).to eq ['5%', '25%', '45%', '65%', '5%']
    end
  end

  context 'normalize_annotation_datetime' do
    before { chart_base.timezone_offset = '-05:00' }

    it 'appends timezone to a plain date' do
      expect(chart_base.normalize_annotation_datetime('2022-06-01')).to eq '2022-06-01T00:00:00-05:00'
    end

    it 'appends timezone to a datetime without timezone' do
      expect(chart_base.normalize_annotation_datetime('2022-06-01T10:30:00')).to eq '2022-06-01T10:30:00-05:00'
    end

    it 'leaves a datetime with explicit + offset unchanged' do
      expect(chart_base.normalize_annotation_datetime('2022-06-01T10:30:00+02:00')).to eq '2022-06-01T10:30:00+02:00'
    end

    it 'leaves a datetime with Z suffix unchanged' do
      expect(chart_base.normalize_annotation_datetime('2022-06-01T10:30:00Z')).to eq '2022-06-01T10:30:00Z'
    end

    it 'falls back to +00:00 when timezone_offset is nil' do
      chart_base.timezone_offset = nil
      expect(chart_base.normalize_annotation_datetime('2022-06-01')).to eq '2022-06-01T00:00:00+00:00'
    end
  end

  context 'date_annotation' do
    before do
      chart_base.date_range = Date.parse('2022-01-01')..Date.parse('2022-12-31')
      chart_base.timezone_offset = '+00:00'
    end

    it 'returns empty string when no annotations configured' do
      chart_base.settings = {}
      expect(chart_base.date_annotation).to eq ''
    end

    it 'returns empty string when date_annotations is empty' do
      chart_base.settings = { 'date_annotations' => [] }
      expect(chart_base.date_annotation).to eq ''
    end

    it 'includes annotation for a plain date within range' do
      chart_base.settings = { 'date_annotations' => [{ 'date' => '2022-06-01', 'label' => 'Coaching started' }] }
      result = chart_base.date_annotation
      expect(result).to include('"2022-06-01T00:00:00+00:00"')
      expect(result).to include('"Coaching started"')
      expect(result).to include('dateAnnotation0:')
      expect(result).to include('position: "5%"')
    end

    it 'staggers labels for close annotations' do
      chart_base.settings = {
        'date_annotations' => [
          { 'date' => '2022-06-01', 'label' => 'First' },
          { 'date' => '2022-06-03', 'label' => 'Second' }
        ]
      }
      result = chart_base.date_annotation
      expect(result).to include('position: "5%"')
      expect(result).to include('position: "25%"')
    end

    it 'includes annotation for a datetime within range' do
      chart_base.settings = { 'date_annotations' => [{ 'date' => '2022-06-01T10:00:00', 'label' => 'Meeting' }] }
      result = chart_base.date_annotation
      expect(result).to include('"2022-06-01T10:00:00+00:00"')
      expect(result).to include('dateAnnotation0:')
    end

    it 'includes annotation for a datetime with explicit timezone' do
      chart_base.settings = { 'date_annotations' => [{ 'date' => '2022-06-01T10:00:00-05:00', 'label' => 'Meeting' }] }
      result = chart_base.date_annotation
      expect(result).to include('"2022-06-01T10:00:00-05:00"')
    end

    it 'excludes annotation for a date outside range' do
      chart_base.settings = { 'date_annotations' => [{ 'date' => '2021-01-01', 'label' => 'Old event' }] }
      expect(chart_base.date_annotation).to eq ''
    end

    it 'numbers multiple annotations sequentially' do
      chart_base.settings = {
        'date_annotations' => [
          { 'date' => '2022-03-01', 'label' => 'First' },
          { 'date' => '2022-09-01', 'label' => 'Second' }
        ]
      }
      result = chart_base.date_annotation
      expect(result).to include('dateAnnotation0:')
      expect(result).to include('dateAnnotation1:')
    end

    it 'filters out-of-range annotations while keeping in-range ones' do
      chart_base.settings = {
        'date_annotations' => [
          { 'date' => '2021-01-01', 'label' => 'Too early' },
          { 'date' => '2022-06-01', 'label' => 'In range' }
        ]
      }
      result = chart_base.date_annotation
      expect(result).to include('dateAnnotation0:')
      expect(result).not_to include('dateAnnotation1:')
      expect(result).to include('"In range"')
      expect(result).not_to include('"Too early"')
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

        board.cycletime = CycleTimeConfig.new(
          possible_statuses: nil, label: 'default', block: block, today: today, settings: load_settings
        )
      end
    end

    it 'handles todo statuses' do
      status = board.possible_statuses.find { |s| s.name == 'Backlog' }
      expect(chart_base.format_status status, board: board).to eq(
        "<span title='Category: \"To Do\":2'><div class='color_block' " \
          "style='background: var(--status-category-todo-color);'></div> \"Backlog\":10000</span>" \
          "<span title='Not visible: The status \"Backlog\" is not mapped to any column and " \
          "will not be visible' style='font-size: 0.8em;'> 👀</span>"
      )
    end

    it 'handles in progress statuses' do
      status = board.possible_statuses.find { |s| s.name == 'Review' }
      expect(chart_base.format_status status, board: board).to eq(
        "<span title='Category: \"In Progress\":4'><div class='color_block' " \
          "style='background: var(--status-category-inprogress-color);'></div> \"Review\":10011</span>"
      )
    end

    it 'handles done statuses' do
      status = board.possible_statuses.find { |s| s.name == 'Done' }
      expect(chart_base.format_status status, board: board).to eq(
        "<span title='Category: \"Done\":3'><div class='color_block' " \
          "style='background: var(--status-category-done-color);'></div> \"Done\":10002</span>"
      )
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
    status = Status.new(name: 'unknown', id: 5, category_name: 'ToDo', category_key: 'unknown', category_id: 2)
    expect(chart_base.status_category_color(status)).to eq CssVariable['--status-category-unknown-color']
  end

  it 'returns reasonable random color' do
    # Since it's random, all we can verify is the format.
    expect(chart_base.random_color).to match(/^#[0-9a-f]{6}$/)
  end

  context 'to_human_readable' do
    it 'returns small numbers unchanged' do
      expect(chart_base.to_human_readable(999)).to eq '999'
    end

    it 'adds a comma for thousands' do
      expect(chart_base.to_human_readable(1000)).to eq '1,000'
    end

    it 'adds commas for millions' do
      expect(chart_base.to_human_readable(1_000_000)).to eq '1,000,000'
    end

    it 'handles zero' do
      expect(chart_base.to_human_readable(0)).to eq '0'
    end
  end
end
