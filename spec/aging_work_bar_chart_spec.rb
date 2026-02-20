# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkBarChart do
  let(:exporter) { Exporter.new(file_system: MockFileSystem.new) }
  let(:chart) do
    described_class.new(empty_config_block).tap do |chart|
      chart.file_system = exporter.file_system
      chart.timezone_offset = '+0000'
    end
  end
  let(:board) { sample_board }
  let(:issue1) { load_issue('SP-1', board: board) }
  let(:issue2) { load_issue('SP-2', board: board) }

  context 'collect_status_ranges' do
    it 'starts on creation and has no further status changes' do
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.timezone_offset = '+0000'
      board = sample_board
      backlog_status = board.possible_statuses.find_by_id!(10_000)
      issue = empty_issue created: '2021-01-01', board: sample_board, creation_status: backlog_status
      issue.board.cycletime = mock_cycletime_config(stub_values: [[issue, '2021-01-01', nil]])

      expect(chart.collect_status_ranges issue: issue, now: to_time('2021-01-05')).to eq [
        BarChartRange.new(start: to_time('2021-01-01'), stop: to_time('2021-01-05'),
          color: CssVariable['--status-category-todo-color'], title: '"Backlog":10000')
      ]
    end

    it 'starts between status changes' do
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.timezone_offset = '+0000'
      backlog_status = board.possible_statuses.find_by_id!(10_000)
      inprogress_status = board.possible_statuses.find_by_id!(3)

      issue = empty_issue created: '2021-01-01', board: sample_board, creation_status: backlog_status

      # We want the start time to be in between status changes
      issue.board.cycletime = mock_cycletime_config(stub_values: [[issue, '2021-01-02', nil]])
      add_mock_change(
        issue: issue, field: 'status', value: inprogress_status.name, value_id: inprogress_status.id,
        time: '2021-01-03'
      )
      expect(chart.collect_status_ranges issue: issue, now: to_time('2021-01-05')).to eq [
        BarChartRange.new(start: to_time('2021-01-02'), stop: to_time('2021-01-03'),
          color: CssVariable['--status-category-todo-color'], title: '"Backlog":10000'),
        BarChartRange.new(start: to_time('2021-01-03'), stop: to_time('2021-01-05'),
          color: CssVariable['--status-category-inprogress-color'], title: '"In Progress":3')
      ]
    end
  end

  context 'bar_chart_range_to_data_set' do
    it 'starts on creation and has no further status changes' do
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: sample_board, creation_status: ['Backlog', 10_000]
      issue.board.cycletime = mock_cycletime_config(stub_values: [[issue, '2021-01-01', nil]])

      data_sets = chart.bar_chart_range_to_data_set(
        y_value: 'story 1', stack: 'status', issue_start_time: to_time('2021-01-01'), ranges: [
          BarChartRange.new(
            start: to_time('2021-01-01'), stop: to_time('2021-01-05'),
            color: 'blue', title: 'mytitle', highlight: false
          )
        ]
      )
      expect(data_sets).to eq([
        {
          type: 'bar',
          data: [
            {
              x: ['2021-01-01T00:00:00+0000', '2021-01-05T00:00:00+0000'],
              y: 'story 1',
              title: 'mytitle'
            }
          ],
          backgroundColor: 'blue',
          borderColor: CssVariable['--aging-work-bar-chart-separator-color'],
          borderWidth: { top: 0, right: 1, bottom: 0, left: 0 },
          stacked: true,
          stack: 'status'
        }
      ])
    end
  end

  context 'collect_blocked_stalled_ranges' do
    it 'handles blocked by flag' do
      chart.settings = board.project_config.settings
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Flagged', value: 'Flagged', time: '2021-01-02T01:00:00')
      add_mock_change(issue: issue, field: 'Flagged', value: '',        time: '2021-01-02T02:00:00')

      data_sets = chart.collect_blocked_stalled_ranges(
        issue: issue, issue_start_time: issue.created
      )
      expect(data_sets).to eq [
        BarChartRange.new(start: to_time('2021-01-02T01:00:00'), stop: to_time('2021-01-02T02:00:00'),
          color: CssVariable['--blocked-color'], title: 'Blocked by flag')
      ]
    end

    it 'handles blocked by status' do
      board.possible_statuses << Status.new(
        name: 'Blocked', id: 10, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
      )

      chart.settings = board.project_config.settings
      chart.settings['blocked_statuses'] = ['Blocked']
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2021-01-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2021-01-03')

      data_sets = chart.collect_blocked_stalled_ranges(
        issue: issue, issue_start_time: issue.created
      )
      expect(data_sets).to eq [
        BarChartRange.new(start: to_time('2021-01-02'), stop: to_time('2021-01-03'),
          color: CssVariable['--blocked-color'], title: 'Blocked by status: Blocked')
      ]
    end

    it 'handle blocked by issue' do
      chart.settings = board.project_config.settings
      chart.settings['blocked_link_text'] = ['is blocked by']

      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      add_mock_change(
        issue: issue, field: 'Link', value: 'This issue is blocked by SP-10', time: '2021-01-02'
      )
      add_mock_change(
        issue: issue, field: 'Link', value: nil, old_value: 'This issue is blocked by SP-10', time: '2021-01-03'
      )

      data_sets = chart.collect_blocked_stalled_ranges(
        issue: issue, issue_start_time: issue.created
      )
      expect(data_sets).to eq [
        BarChartRange.new(start: to_time('2021-01-02'), stop: to_time('2021-01-03'),
          color: CssVariable['--blocked-color'], title: 'Blocked by issues: SP-10')
      ]
    end
  end

  context 'sort_by_age!' do
    it 'leaves an already sorted list alone' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', nil],
        [issue2, '2024-01-02', nil]
      ]
      expect(chart.sort_by_age! issues: [issue1, issue2], today: to_date('2024-01-05')).to eq [
        issue1, issue2
      ]
    end

    it 'sorts the list' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-02', nil],
        [issue2, '2024-01-01', nil]
      ]
      expect(chart.sort_by_age! issues: [issue1, issue2], today: to_date('2024-01-05')).to eq [
        issue2, issue1
      ]
    end
  end

  context 'select_aging_issues' do
    it 'returns empty when no issues' do
      expect(chart.select_aging_issues issues: []).to be_empty
    end

    it 'selects only aging' do
      issue3 = load_issue 'SP-1', board: board
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-05')
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil],                  # not started
        [issue2, '2024-01-01', nil],         # started
        [issue3, '2024-01-01', '2024-01-05'] # completed
      ]
      expect(chart.select_aging_issues issues: [issue1, issue2, issue3]).to eq [issue2]
    end

    it 'excludes any that were ignored in the grouping rules', :focus do
      chart = described_class.new ->(_) { age_cutoff 3 }
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-05')
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', nil],
        [issue2, '2024-01-05', nil]
      ]
      expect(chart.select_aging_issues issues: [issue1, issue2]).to eq [issue1]
    end
  end

  context 'collect_priority_ranges' do
    it 'handles no priority changes' do
      issue = empty_issue created: '2021-01-02'
      chart.settings = board.project_config.settings
      chart.time_range = to_time('2021-01-01')..to_time('2021-01-10')
      expect(chart.collect_priority_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-02'), stop: to_time('2021-01-10'),
          color: CssVariable['--priority-color-medium'],
          title: 'Priority: Medium'
        )
      ]
    end

    it 'handles priority changes' do
      issue = empty_issue created: '2021-01-02'
      chart.settings = board.project_config.settings
      chart.time_range = to_time('2021-01-01')..to_time('2021-01-10')

      add_mock_change(
        issue: issue, field: 'priority', value: 'Highest', time: '2021-01-03'
      )

      expect(chart.collect_priority_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-02'), stop: to_time('2021-01-03'),
          color: CssVariable['--priority-color-medium'],
          title: 'Priority: Medium'
        ),
        BarChartRange.new(
          start: to_time('2021-01-03'), stop: to_time('2021-01-10'),
          color: CssVariable['--priority-color-highest'],
          title: 'Priority: Highest (expedited)', highlight: true
        )
      ]
    end
  end

  context 'calculate_percent_line' do
    it 'returns nil when no issues' do
      chart.issues = []
      expect(chart.calculate_percent_line).to be_nil
    end

    it 'returns percentage' do
      issue1 = empty_issue key: 'SP-1', created: '2024-01-01', board: board
      issue2 = empty_issue key: 'SP-2', created: '2024-01-01', board: board
      issue3 = empty_issue key: 'SP-3', created: '2024-01-01', board: board

      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', '2024-01-10'], # age 10
        [issue2, '2024-01-01', '2024-01-20'], # age 20
        [issue3, '2024-01-01', '2024-01-30']  # age 30
      ]
      chart.issues = [issue1, issue2, issue3]
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')

      expect(chart.calculate_percent_line percentage: 5).to eq 10
      expect(chart.calculate_percent_line percentage: 45).to eq 20
      expect(chart.calculate_percent_line percentage: 95).to eq 30
    end
  end

  context 'grow_chart_height_if_too_many_issues' do
    it 'is the minimum height when only one issue' do
      chart.grow_chart_height_if_too_many_issues aging_issue_count: 1
      expect(chart.canvas_height).to eq 80
    end

    it 'ignores this when a larger height was already specified' do
      chart.grow_chart_height_if_too_many_issues aging_issue_count: 1
      chart.canvas width: 10, height: 100
      expect(chart.canvas_height).to eq 100
    end

    it 'grows as needed' do
      chart.grow_chart_height_if_too_many_issues aging_issue_count: 100
      expect(chart.canvas_height).to eq 3000
    end
  end

  context 'run' do
    it 'escapes early if no active items' do
      chart.issues = []
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')
      chart.time_range = to_time('2024-01-01')..to_time('2024-01-31')

      expect(chart.run).to eq "<h1 class='foldable'>Aging Work Bar Chart</h1><p>There is no aging work</p>"
    end
  end

  context 'adjust_time_date_ranges_to_start_from_earliest_issue_start' do
    it 'doesn\'t do anything when the earliest is already inside the normal range' do
      chart.time_range = to_time('2021-03-01')..to_time('2021-05-30') # 90 days
      chart.date_range = to_date('2021-03-01')..to_date('2021-05-30') # 90 days
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2021-03-02'), nil]
      ]
      chart.adjust_time_date_ranges_to_start_from_earliest_issue_start([issue1])
      expect(chart.time_range).to eq(to_time('2021-03-01')..to_time('2021-05-30'))
      expect(chart.date_range).to eq(to_date('2021-03-01')..to_date('2021-05-30'))
    end

    it 'adjusts time and date' do
      chart.time_range = to_time('2021-03-01')..to_time('2021-05-30') # 90 days
      chart.date_range = to_date('2021-03-01')..to_date('2021-05-30') # 90 days
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2021-02-01'), nil]
      ]
      chart.adjust_time_date_ranges_to_start_from_earliest_issue_start([issue1])
      expect(chart.time_range).to eq(to_time('2021-02-01')..to_time('2021-05-30'))
      expect(chart.date_range).to eq(to_date('2021-02-01')..to_date('2021-05-30'))
    end
  end

  context 'collect_sprint_ranges' do
    let(:sprint1) do
      Sprint.new(
        raw: {
          'id' => 1,
          'state' => 'closed',
          'name' => 'Sprint 1',
          'activatedDate' => '2021-01-03T00:00:00+00:00',
          'endDate' => '2021-01-17T00:00:00+00:00',
          'completeDate' => '2021-01-17T00:00:00+00:00'
        },
        timezone_offset: '+0000'
      )
    end

    before do
      board.sprints << sprint1
      chart.time_range = to_time('2021-01-01')..to_time('2021-01-20')
    end

    it 'returns empty when there are no sprint changes' do
      issue = empty_issue created: '2021-01-01', board: board
      expect(chart.collect_sprint_ranges(issue: issue)).to eq []
    end

    it 'returns a range for a closed sprint the issue was in' do
      issue = empty_issue created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: sprint1.name, value_id: sprint1.id.to_s, time: '2021-01-05')

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-05'), stop: to_time('2021-01-17'),
          color: CssVariable['--sprint-color'], title: 'Sprint 1'
        )
      ]
    end

    it 'uses the sprint start time when the issue was added before the sprint began' do
      issue = empty_issue created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: sprint1.name, value_id: sprint1.id.to_s, time: '2021-01-01')

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-03'), stop: to_time('2021-01-17'),
          color: CssVariable['--sprint-color'], title: 'Sprint 1'
        )
      ]
    end

    it 'uses time_range.end when the sprint is still active' do
      active_sprint = Sprint.new(
        raw: {
          'id' => 2,
          'state' => 'active',
          'name' => 'Sprint 2',
          'activatedDate' => '2021-01-03T00:00:00+00:00',
          'endDate' => '2021-01-17T00:00:00+00:00'
        },
        timezone_offset: '+0000'
      )
      board.sprints << active_sprint

      issue = empty_issue created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: active_sprint.name, value_id: active_sprint.id.to_s, time: '2021-01-05')

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-05'), stop: to_time('2021-01-20'),
          color: CssVariable['--sprint-color'], title: 'Sprint 2'
        )
      ]
    end

    it 'ends the range when the issue is removed from the sprint' do
      issue = empty_issue created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: sprint1.name, value_id: sprint1.id.to_s, time: '2021-01-05')
      add_mock_change(
        issue: issue, field: 'Sprint', value: '', value_id: '',
        old_value: sprint1.name, old_value_id: sprint1.id.to_s,
        time: '2021-01-10'
      )

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-05'), stop: to_time('2021-01-10'),
          color: CssVariable['--sprint-color'], title: 'Sprint 1'
        )
      ]
    end

    it 'returns no range for a future sprint' do
      future_sprint = Sprint.new(
        raw: {
          'id' => 3,
          'state' => 'future',
          'name' => 'Sprint 3',
          'startDate' => '2021-02-01T00:00:00+00:00',
          'endDate' => '2021-02-14T00:00:00+00:00'
        },
        timezone_offset: '+0000'
      )
      board.sprints << future_sprint

      issue = empty_issue created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: future_sprint.name, value_id: future_sprint.id.to_s, time: '2021-01-05')

      expect(chart.collect_sprint_ranges(issue: issue)).to eq []
    end

    it 'returns ranges for two consecutive sprints' do
      sprint2 = Sprint.new(
        raw: {
          'id' => 2,
          'state' => 'active',
          'name' => 'Sprint 2',
          'activatedDate' => '2021-01-18T00:00:00+00:00',
          'endDate' => '2021-02-01T00:00:00+00:00'
        },
        timezone_offset: '+0000'
      )
      board.sprints << sprint2

      issue = empty_issue created: '2021-01-01', board: board
      # Added to sprint 1
      add_mock_change(issue: issue, field: 'Sprint', value: sprint1.name, value_id: sprint1.id.to_s, time: '2021-01-05')
      # Moved from sprint 1 to sprint 2
      add_mock_change(
        issue: issue, field: 'Sprint', value: sprint2.name, value_id: sprint2.id.to_s,
        old_value: sprint1.name, old_value_id: sprint1.id.to_s,
        time: '2021-01-18'
      )

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-05'), stop: to_time('2021-01-17'),
          color: CssVariable['--sprint-color'], title: 'Sprint 1'
        ),
        BarChartRange.new(
          start: to_time('2021-01-18'), stop: to_time('2021-01-20'),
          color: CssVariable['--sprint-color'], title: 'Sprint 2'
        )
      ]
    end
  end
end
