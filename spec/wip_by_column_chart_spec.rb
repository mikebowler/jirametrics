# frozen_string_literal: true

require './spec/spec_helper'

describe WipByColumnChart do
  # Sample board 1 visible columns (kanban, Backlog dropped):
  #   index 0: "Ready"       status 10001 "Selected for Development"  min=1 max=4
  #   index 1: "In Progress" status 3     "In Progress"               min=nil max=3
  #   index 2: "Review"      status 10011 "Review"                    min=nil max=3
  #   index 3: "Done"        status 10002 "Done"                      min=nil max=nil

  let(:board) do
    load_complete_sample_board.tap do |b|
      b.cycletime = default_cycletime_config
    end
  end

  let(:chart) do
    chart = described_class.new(empty_config_block)
    chart.board_id = 1
    chart.all_boards = { 1 => board }
    # 1000-second window for clean arithmetic
    chart.time_range = to_time('2021-06-01T00:00:00')..to_time('2021-06-01T00:16:40')
    chart.date_range = to_date('2021-06-01')..to_date('2021-06-01')
    chart
  end

  # Build a pair of issues that are in "Selected for Development" before the window and have no
  # resolution, so default_cycletime_config considers them in WIP throughout the window.
  def issue_in_ready key:
    issue = empty_issue created: '2021-05-31', board: board, key: key
    add_mock_change issue: issue, field: 'status',
      value: 'Selected for Development', value_id: 10_001,
      time: to_time('2021-05-31T12:00:00')
    issue
  end

  context 'column_stats' do
    it 'returns one ColumnStats per visible column' do
      chart.issues = []
      expect(chart.column_stats.size).to eq board.visible_columns.size
    end

    it 'populates the column name and wip limits from the board column' do
      chart.issues = []
      stats = chart.column_stats

      expect(stats[0].name).to eq 'Ready'
      expect(stats[0].min_wip_limit).to eq 1   # Ready min
      expect(stats[0].max_wip_limit).to eq 4   # Ready max
      expect(stats[1].name).to eq 'In Progress'
      expect(stats[1].min_wip_limit).to be_nil # In Progress min
      expect(stats[1].max_wip_limit).to eq 3   # In Progress max
      expect(stats[3].max_wip_limit).to be_nil # Done max
    end

    it 'tracks time spent at each WIP level as issues move between columns' do
      # Issue A: in Ready at start, moves to In Progress halfway through
      issue_a = issue_in_ready key: 'SP-1'
      add_mock_change issue: issue_a, field: 'status',
        value: 'In Progress', value_id: 3,
        time: to_time('2021-06-01T00:08:20') # 500s into the window

      # Issue B: in Ready the entire window
      issue_b = issue_in_ready key: 'SP-2'

      chart.issues = [issue_a, issue_b]
      stats = chart.column_stats

      # Ready: WIP=2 for first 500s, WIP=1 for last 500s
      expect(stats[0].wip_history).to eq [[1, 500], [2, 500]]

      # In Progress: WIP=0 for first 500s, WIP=1 for last 500s
      expect(stats[1].wip_history).to eq [[0, 500], [1, 500]]
    end

    it 'excludes issues belonging to a different board' do
      json = JSON.parse(file_read('./spec/complete_sample/sample_board_1_configuration.json'))
      json['id'] = 2
      other_board = Board.new(raw: json, possible_statuses: load_complete_sample_statuses)
      other_board.cycletime = default_cycletime_config

      issue_other = empty_issue created: '2021-05-31', board: other_board, key: 'SP-99'
      add_mock_change issue: issue_other, field: 'status',
        value: 'Selected for Development', value_id: 10_001,
        time: to_time('2021-05-31T12:00:00')

      chart.issues = [issue_other]
      stats = chart.column_stats

      expect(stats.all? { |s| s.wip_history.all? { |wip, _| wip.zero? } }).to be true
    end

    it 'handles an issue that first appears within the time range' do
      # Issue with no status change before the window starts
      issue = empty_issue created: '2021-06-01', board: board, key: 'SP-1'
      add_mock_change issue: issue, field: 'status',
        value: 'Selected for Development', value_id: 10_001,
        time: to_time('2021-06-01T00:08:20') # 500s in

      chart.issues = [issue]
      stats = chart.column_stats

      # Ready: WIP=0 for first 500s, WIP=1 for last 500s
      expect(stats[0].wip_history).to eq [[0, 500], [1, 500]]
    end

    it 'handles simultaneous status changes correctly' do
      issue_a = issue_in_ready key: 'SP-1'
      add_mock_change issue: issue_a, field: 'status',
        value: 'In Progress', value_id: 3,
        time: to_time('2021-06-01T00:08:20')

      issue_b = issue_in_ready key: 'SP-2'
      add_mock_change issue: issue_b, field: 'status',
        value: 'In Progress', value_id: 3,
        time: to_time('2021-06-01T00:08:20') # same time as issue_a

      chart.issues = [issue_a, issue_b]
      stats = chart.column_stats

      # Ready: WIP=2 for 500s, WIP=0 for 500s
      expect(stats[0].wip_history).to eq [[0, 500], [2, 500]]
      # In Progress: WIP=0 for 500s, WIP=2 for 500s
      expect(stats[1].wip_history).to eq [[0, 500], [2, 500]]
    end

    context 'respects started and stopped times from the cycletime config' do
      it 'excludes an issue that has not yet started at the window boundary' do
        issue = issue_in_ready key: 'SP-1'
        board.cycletime = mock_cycletime_config stub_values: [
          ['SP-1', '2021-06-01T00:08:20', nil] # starts 500s into the window
        ]

        chart.issues = [issue]
        stats = chart.column_stats

        # Issue is not in WIP for the first 500s, then enters Ready
        expect(stats[0].wip_history).to eq [[0, 500], [1, 500]]
      end

      it 'removes an issue from WIP when it stops within the window' do
        issue = issue_in_ready key: 'SP-1'
        board.cycletime = mock_cycletime_config stub_values: [
          ['SP-1', '2021-05-31T12:00:00', '2021-06-01T00:08:20'] # stops 500s into the window
        ]

        chart.issues = [issue]
        stats = chart.column_stats

        # Issue is in Ready for the first 500s, then leaves WIP
        expect(stats[0].wip_history).to eq [[0, 500], [1, 500]]
      end

      it 'excludes an issue that was already done before the window opened' do
        issue = issue_in_ready key: 'SP-1'
        board.cycletime = mock_cycletime_config stub_values: [
          ['SP-1', '2021-05-31T10:00:00', '2021-05-31T23:00:00'] # done before window
        ]

        chart.issues = [issue]
        stats = chart.column_stats

        expect(stats.all? { |s| s.wip_history.all? { |wip, _| wip.zero? } }).to be true
      end
    end
  end
end
