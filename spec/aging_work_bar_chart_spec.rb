# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkBarChart do
  let(:exporter) { Exporter.new(file_system: MockFileSystem.new) }
  let(:board) { sample_board }
  let(:chart) do
    described_class.new(empty_config_block).tap do |chart|
      chart.file_system = exporter.file_system
      chart.timezone_offset = '+0000'
      chart.all_boards = { board.id => board }
    end
  end
  let(:issue1) { load_issue('SP-1', board: board) }
  let(:issue2) { load_issue('SP-2', board: board) }

  describe '#description_text' do
    it 'mentions four bars and includes sprints item for scrum board' do
      board.raw['type'] = 'scrum'
      rendered = ERB.new(chart.description_text).result(chart.instance_eval { binding })
      aggregate_failures do
        expect(rendered).to include('four bars')
        expect(rendered).to include('Sprints')
      end
    end

    it 'mentions three bars and excludes sprints item for kanban board' do
      board.raw['type'] = 'kanban'
      rendered = ERB.new(chart.description_text).result(chart.instance_eval { binding })
      aggregate_failures do
        expect(rendered).to include('three bars')
        expect(rendered).not_to include('Sprints')
      end
    end
  end

  describe '#collect_status_ranges' do
    it 'starts on creation and has no further status changes' do
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.timezone_offset = '+0000'
      board = sample_board
      backlog_status = board.possible_statuses.find_by_id!(10_000)
      issue = MockIssue.empty created: '2021-01-01', board: sample_board, creation_status: backlog_status
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

      issue = MockIssue.empty created: '2021-01-01', board: sample_board, creation_status: backlog_status

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

  describe '#bar_chart_range_to_data_set' do
    it 'starts on creation and has no further status changes' do
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.timezone_offset = '+0000'
      issue = MockIssue.empty created: '2021-01-01', board: sample_board, creation_status: ['Backlog', 10_000]
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

  describe '#collect_blocked_stalled_ranges' do
    it 'handles blocked by flag' do
      chart.settings = board.project_config.settings
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = MockIssue.empty created: '2021-01-01', board: board
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
      chart.settings['blocked_statuses'] = status_collection_for(board: board, names: ['Blocked'])
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = MockIssue.empty created: '2021-01-01', board: board
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
      issue = MockIssue.empty created: '2021-01-01', board: board
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

    # A flag on then off, giving a single blocked span from 01-02T01 to 01-02T02.
    def flagged_issue
      chart.settings = board.project_config.settings
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      MockIssue.empty(created: '2021-01-01', board: board).tap do |issue|
        add_mock_change(issue: issue, field: 'Flagged', value: 'Flagged', time: '2021-01-02T01:00:00')
        add_mock_change(issue: issue, field: 'Flagged', value: '', time: '2021-01-02T02:00:00')
      end
    end

    it 'excludes a span that ends before the issue started' do
      issue = flagged_issue
      ranges = chart.collect_blocked_stalled_ranges(issue: issue, issue_start_time: to_time('2021-01-03'))
      expect(ranges).to be_empty
    end

    it 'includes a span whose end is exactly the issue start time' do
      issue = flagged_issue
      ranges = chart.collect_blocked_stalled_ranges(issue: issue, issue_start_time: to_time('2021-01-02T02:00:00'))
      expect(ranges.size).to eq 1
    end

    # A status change into a stalled status and back out, giving a stalled span from 01-02 to 01-03.
    def stalled_issue
      board.possible_statuses << Status.new(
        name: 'Waiting', id: 11, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
      )
      chart.settings = board.project_config.settings
      chart.settings['stalled_statuses'] = status_collection_for(board: board, names: ['Waiting'])
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      MockIssue.empty(created: '2021-01-01', board: board).tap do |issue|
        add_mock_change(issue: issue, field: 'status', value: 'Waiting', value_id: 11, time: '2021-01-02')
        add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2021-01-03')
      end
    end

    it 'uses the stalled color for a stalled span' do
      issue = stalled_issue
      ranges = chart.collect_blocked_stalled_ranges(issue: issue, issue_start_time: issue.created)
      expect(ranges).to eq [
        BarChartRange.new(start: to_time('2021-01-02'), stop: to_time('2021-01-03'),
          color: CssVariable['--stalled-color'], title: 'Stalled by status: Waiting')
      ]
    end

    it 'emits separate ranges when a blocked span runs straight into a stalled span' do
      board.possible_statuses << Status.new(
        name: 'Blocked', id: 10, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
      )
      board.possible_statuses << Status.new(
        name: 'Waiting', id: 11, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
      )
      chart.settings = board.project_config.settings
      chart.settings['blocked_statuses'] = status_collection_for(board: board, names: ['Blocked'])
      chart.settings['stalled_statuses'] = status_collection_for(board: board, names: ['Waiting'])
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2021-01-02')
      add_mock_change(issue: issue, field: 'status', value: 'Waiting', value_id: 11, time: '2021-01-03')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2021-01-04')

      ranges = chart.collect_blocked_stalled_ranges(issue: issue, issue_start_time: issue.created)
      expect(ranges.collect(&:color)).to eq [CssVariable['--blocked-color'], CssVariable['--stalled-color']]
    end
  end

  describe '#sort_by_age!' do
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

  describe '#select_aging_issues' do
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

    it 'excludes any that were ignored in the grouping rules' do
      chart = described_class.new ->(_) { age_cutoff 3 }
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-05')
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', nil],
        [issue2, '2024-01-05', nil]
      ]
      expect(chart.select_aging_issues issues: [issue1, issue2]).to eq [issue1]
    end
  end

  describe '#clip_ranges_to_start_time' do
    let(:color) { CssVariable['--blocked-color'] }

    it 'does nothing when issue_start_time is nil' do
      range = BarChartRange.new(start: to_time('2021-01-01'), stop: to_time('2021-01-05'), color: color, title: 'x')
      ranges = [range]
      chart.clip_ranges_to_start_time(ranges: ranges, issue_start_time: nil)
      expect(ranges).to eq [range]
    end

    it 'does not modify ranges that start after issue_start_time' do
      range = BarChartRange.new(start: to_time('2021-01-03'), stop: to_time('2021-01-05'), color: color, title: 'x')
      chart.clip_ranges_to_start_time(ranges: [range], issue_start_time: to_time('2021-01-02'))
      expect(range.start).to eq to_time('2021-01-03')
    end

    it 'clamps the start of a range that begins before issue_start_time' do
      range = BarChartRange.new(start: to_time('2021-01-01'), stop: to_time('2021-01-05'), color: color, title: 'x')
      chart.clip_ranges_to_start_time(ranges: [range], issue_start_time: to_time('2021-01-03'))
      expect(range.start).to eq to_time('2021-01-03')
    end

    it 'removes a range that ends at or before issue_start_time' do
      range = BarChartRange.new(start: to_time('2021-01-01'), stop: to_time('2021-01-03'), color: color, title: 'x')
      ranges = [range]
      chart.clip_ranges_to_start_time(ranges: ranges, issue_start_time: to_time('2021-01-03'))
      expect(ranges).to be_empty
    end
  end

  describe '#collect_priority_ranges' do
    it 'returns empty array when issue has no priority changes at all' do
      issue = MockIssue.empty created: '2021-01-02'
      issue.changes.reject!(&:priority?)
      chart.settings = board.project_config.settings
      chart.time_range = to_time('2021-01-01')..to_time('2021-01-10')
      expect(chart.collect_priority_ranges(issue: issue)).to eq []
    end

    it 'handles no priority changes' do
      issue = MockIssue.empty created: '2021-01-02'
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
      issue = MockIssue.empty created: '2021-01-02'
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

  describe '#calculate_percent_line' do
    it 'returns nil when no issues' do
      chart.issues = []
      expect(chart.calculate_percent_line).to be_nil
    end

    it 'returns percentage' do
      issue1 = MockIssue.empty key: 'SP-1', created: '2024-01-01', board: board
      issue2 = MockIssue.empty key: 'SP-2', created: '2024-01-01', board: board
      issue3 = MockIssue.empty key: 'SP-3', created: '2024-01-01', board: board

      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', '2024-01-10'], # age 10
        [issue2, '2024-01-01', '2024-01-20'], # age 20
        [issue3, '2024-01-01', '2024-01-30']  # age 30
      ]
      chart.issues = [issue1, issue2, issue3]
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')

      aggregate_failures do
        expect(chart.calculate_percent_line percentage: 5).to eq 10
        expect(chart.calculate_percent_line percentage: 45).to eq 20
        expect(chart.calculate_percent_line percentage: 95).to eq 30
      end
    end

    # The index is length * percentage / 100, which lands one past the end at 100. Unreachable
    # while the percentage was hardcoded to 85; reachable now that it is configurable.
    it 'returns the largest value rather than nil at the top of the range' do
      issue1 = MockIssue.empty key: 'SP-1', created: '2024-01-01', board: board
      issue2 = MockIssue.empty key: 'SP-2', created: '2024-01-01', board: board

      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', '2024-01-10'], # age 10
        [issue2, '2024-01-01', '2024-01-20']  # age 20
      ]
      chart.issues = [issue1, issue2]
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')

      expect(chart.calculate_percent_line percentage: 100).to eq 20
    end
  end

  describe '#priority_color' do
    it 'uses the variable for a priority that has a colour' do
      expect(chart.priority_color('Medium')).to eq CssVariable['--priority-color-medium']
    end

    it 'strips spaces and case the same way the css names do' do
      expect(chart.priority_color('Highest')).to eq CssVariable['--priority-color-highest']
    end

    # Jira admins can define any priority they like, so this is reachable with real data. Two of
    # the sample reports request colours for "Immediate Gating" and "Ignored", neither of which
    # ships a variable.
    it 'warns once, with the line to paste, for a priority that has no colour' do
      chart.priority_color 'Immediate Gating'
      chart.priority_color 'Immediate Gating'
      warnings = chart.file_system.log_messages.select { |m| m.include? 'Immediate Gating' }
      aggregate_failures do
        expect(warnings.size).to eq 1
        expect(warnings.first).to include '--priority-color-immediategating: #0072B2;'
        expect(warnings.first).to include 'include_css'
      end
    end

    it 'still returns a variable for the unknown priority so the chart keeps drawing' do
      expect(chart.priority_color('Ignored')).to eq CssVariable['--priority-color-ignored']
    end
  end

  describe '#percentile_description' do
    # Rendered through run rather than called directly, so this also guards the ERB tag in
    # description_text. It must be <%= percentile_description %>: description_text is built during
    # initialize, before the config block runs, so interpolation would freeze the default in.
    def render_with percentiles
      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/aging_work_bar_chart.erb'), json: :not_mocked
      )
      aging = MockIssue.empty created: '2024-01-15', board: board
      done_early = MockIssue.empty key: 'SP-90', created: '2024-01-01', board: board
      done_late = MockIssue.empty key: 'SP-91', created: '2024-01-01', board: board
      board.cycletime = mock_cycletime_config stub_values: [
        [aging, to_time('2024-01-15'), nil],
        [done_early, to_time('2024-01-01'), to_time('2024-01-05')],
        [done_late, to_time('2024-01-01'), to_time('2024-01-20')]
      ]
      add_mock_change(issue: aging, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-15')
      add_mock_change(issue: aging, field: 'priority', value: 'Medium', time: '2024-01-15')
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')
      chart.time_range = to_time('2024-01-01')..to_time('2024-01-31')
      chart.holiday_dates = []
      chart.settings = board.project_config.settings
      chart.issues = [aging, done_early, done_late]
      chart.percentiles percentiles
      chart.run
    end

    it 'names the single configured percentile and its value' do
      output = render_with [85]
      aggregate_failures do
        expect(output).to include '85th percentile of how long'
        expect(output).to include 'aging longer than 85% of everything'
      end
    end

    it 'lists several percentiles without the singular framing' do
      output = render_with [50, 85]
      aggregate_failures do
        expect(output).to include '50th and 85th percentiles'
        expect(output).not_to include 'aging longer than 50% of everything'
      end
    end

    it 'says nothing about lines when none are drawn' do
      expect(render_with([])).not_to include 'percentile of how long'
    end

    # color_block emits a div. A div inside a p is invalid HTML, so the browser closes the
    # paragraph early and the rest of the sentence escapes it and reflows after the chart.
    it 'does not wrap the colour swatch in a p element' do
      output = render_with [85]
      paragraph = output[%r{<p>[^<]*The vertical.*?</p>}m]
      aggregate_failures do
        expect(paragraph).to be_nil
        expect(output).to match(/<div class="p">\s*The vertical/m)
      end
    end
  end

  describe '#percentiles' do
    it 'defaults to the 85th' do
      expect(chart.percentiles).to eq [85]
    end

    it 'accepts a replacement list' do
      chart.percentiles [50, 85]
      expect(chart.percentiles).to eq [50, 85]
    end

    it 'accepts an empty list to switch the line off' do
      chart.percentiles []
      expect(chart.percentiles).to eq []
    end

    it 'rejects values outside 0..100' do
      expect { chart.percentiles [150] }.to raise_error(
        ArgumentError, /percentile 150 must be between 0 and 100/
      )
    end

    it 'removes duplicates and sorts' do
      chart.percentiles [85, 50, 85]
      expect(chart.percentiles).to eq [50, 85]
    end
  end

  describe '#grow_chart_height_if_too_many_issues' do
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

  describe '#run' do
    it 'escapes early if no active items' do
      chart.issues = []
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')
      chart.time_range = to_time('2024-01-01')..to_time('2024-01-31')

      expect(chart.run).to eq "<h1 class='foldable'>Aging Work Bar Chart</h1><p>There is no aging work</p>"
    end

    it 'sets x-axis max to one day past date_range.end' do
      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/aging_work_bar_chart.erb'),
        json: :not_mocked
      )
      issue = MockIssue.empty created: '2024-01-15', board: board
      board.cycletime = mock_cycletime_config stub_values: [[issue, to_time('2024-01-15'), nil]]
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-15')
      add_mock_change(issue: issue, field: 'priority', value: 'Medium', time: '2024-01-15')

      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')
      chart.time_range = to_time('2024-01-01')..to_time('2024-01-31')
      chart.holiday_dates = []
      chart.settings = board.project_config.settings
      chart.issues = [issue]

      output = chart.run
      expect(output).to include("max: '2024-02-01'")
    end

    # These annotations are hand written into the ERB, so a missing comma or an unquoted key
    # breaks the whole chart script at runtime while every Ruby test still passes.
    it 'renders one annotation per configured percentile' do
      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/aging_work_bar_chart.erb'),
        json: :not_mocked
      )
      aging = MockIssue.empty created: '2024-01-15', board: board
      done_early = MockIssue.empty key: 'SP-90', created: '2024-01-01', board: board
      done_late = MockIssue.empty key: 'SP-91', created: '2024-01-01', board: board
      board.cycletime = mock_cycletime_config stub_values: [
        [aging, to_time('2024-01-15'), nil],
        [done_early, to_time('2024-01-01'), to_time('2024-01-05')],
        [done_late, to_time('2024-01-01'), to_time('2024-01-20')]
      ]
      add_mock_change(issue: aging, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-15')
      add_mock_change(issue: aging, field: 'priority', value: 'Medium', time: '2024-01-15')

      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')
      chart.time_range = to_time('2024-01-01')..to_time('2024-01-31')
      chart.holiday_dates = []
      chart.settings = board.project_config.settings
      chart.issues = [aging, done_early, done_late]
      chart.percentiles [50, 85]

      output = chart.run
      aggregate_failures do
        expect(output).to include '"percentile_50":'
        expect(output).to include '"percentile_85":'
        expect(output).to include '50th percentile of completed work'
      end
    end

    it 'renders no percentile annotations when the list is empty' do
      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/aging_work_bar_chart.erb'),
        json: :not_mocked
      )
      issue = MockIssue.empty created: '2024-01-15', board: board
      board.cycletime = mock_cycletime_config stub_values: [[issue, to_time('2024-01-15'), nil]]
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-15')
      add_mock_change(issue: issue, field: 'priority', value: 'Medium', time: '2024-01-15')

      chart.date_range = to_date('2024-01-01')..to_date('2024-01-31')
      chart.time_range = to_time('2024-01-01')..to_time('2024-01-31')
      chart.holiday_dates = []
      chart.settings = board.project_config.settings
      chart.issues = [issue]
      chart.percentiles []

      expect(chart.run).not_to include 'percentile_'
    end
  end

  describe '#adjust_time_date_ranges_to_start_from_earliest_issue_start' do
    it 'doesn\'t do anything when the earliest is already inside the normal range' do
      chart.time_range = to_time('2021-03-01')..to_time('2021-05-30') # 90 days
      chart.date_range = to_date('2021-03-01')..to_date('2021-05-30') # 90 days
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2021-03-02'), nil]
      ]
      chart.adjust_time_date_ranges_to_start_from_earliest_issue_start([issue1])
      aggregate_failures do
        expect(chart.time_range).to eq(to_time('2021-03-01')..to_time('2021-05-30'))
        expect(chart.date_range).to eq(to_date('2021-03-01')..to_date('2021-05-30'))
      end
    end

    it 'adjusts time and date' do
      chart.time_range = to_time('2021-03-01')..to_time('2021-05-30') # 90 days
      chart.date_range = to_date('2021-03-01')..to_date('2021-05-30') # 90 days
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2021-02-01'), nil]
      ]
      chart.adjust_time_date_ranges_to_start_from_earliest_issue_start([issue1])
      aggregate_failures do
        expect(chart.time_range).to eq(to_time('2021-02-01')..to_time('2021-05-30'))
        expect(chart.date_range).to eq(to_date('2021-02-01')..to_date('2021-05-30'))
      end
    end
  end

  describe '#collect_sprint_ranges' do
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
      issue = MockIssue.empty created: '2021-01-01', board: board
      expect(chart.collect_sprint_ranges(issue: issue)).to eq []
    end

    it 'returns a range for a closed sprint the issue was in' do
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: sprint1.name, value_id: sprint1.id.to_s, time: '2021-01-05')

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-05'), stop: to_time('2021-01-17'),
          color: CssVariable['--sprint-color'], title: 'Sprint 1'
        )
      ]
    end

    it 'uses the sprint start time when the issue was added before the sprint began' do
      issue = MockIssue.empty created: '2021-01-01', board: board
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

      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: active_sprint.name, value_id: active_sprint.id.to_s,
time: '2021-01-05')

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-05'), stop: to_time('2021-01-20'),
          color: CssVariable['--sprint-color'], title: 'Sprint 2'
        )
      ]
    end

    it 'ends the range when the issue is removed from the sprint' do
      issue = MockIssue.empty created: '2021-01-01', board: board
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

      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: future_sprint.name, value_id: future_sprint.id.to_s,
time: '2021-01-05')

      expect(chart.collect_sprint_ranges(issue: issue)).to eq []
    end

    it 'ignores a future sprint when an issue is moved from a closed sprint to a future sprint' do
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

      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: sprint1.name, value_id: sprint1.id.to_s, time: '2021-01-05')
      add_mock_change(
        issue: issue, field: 'Sprint', value: future_sprint.name, value_id: future_sprint.id.to_s,
        old_value: sprint1.name, old_value_id: sprint1.id.to_s,
        time: '2021-01-15'
      )

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(
          start: to_time('2021-01-05'), stop: to_time('2021-01-15'),
          color: CssVariable['--sprint-color'], title: 'Sprint 1'
        )
      ]
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

      issue = MockIssue.empty created: '2021-01-01', board: board
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

    def active_sprint id, name, start
      Sprint.new(
        raw: { 'id' => id, 'state' => 'active', 'name' => name,
               'activatedDate' => "#{start}T00:00:00+00:00", 'endDate' => '2021-02-01T00:00:00+00:00' },
        timezone_offset: '+0000'
      )
    end

    it 'keeps a sprint open across a change that adds another' do
      board.sprints << active_sprint(2, 'Sprint 2', '2021-01-08')
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: sprint1.name, value_id: '1', time: '2021-01-05')
      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1, Sprint 2', value_id: '1, 2',
        old_value: sprint1.name, old_value_id: '1', time: '2021-01-10'
      )

      sprint1_range = chart.collect_sprint_ranges(issue: issue).find { |range| range.title == 'Sprint 1' }
      aggregate_failures do
        expect(sprint1_range.start).to eq to_time('2021-01-05') # not reset by the second change
        expect(sprint1_range.stop).to eq to_time('2021-01-17')  # not cut short at 01-10
      end
    end

    it 'stops at the removal time when an active sprint (no completion) is left' do
      board.sprints << active_sprint(2, 'Sprint 2', '2021-01-03')
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: 'Sprint 2', value_id: '2', time: '2021-01-05')
      add_mock_change(
        issue: issue, field: 'Sprint', value: '', value_id: '', old_value: 'Sprint 2', old_value_id: '2',
        time: '2021-01-10'
      )

      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(start: to_time('2021-01-05'), stop: to_time('2021-01-10'),
          color: CssVariable['--sprint-color'], title: 'Sprint 2')
      ]
    end

    it 'ignores a removal for a sprint that was never added' do
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(
        issue: issue, field: 'Sprint', value: '', value_id: '', old_value: sprint1.name, old_value_id: '1',
        time: '2021-01-10'
      )
      expect(chart.collect_sprint_ranges(issue: issue)).to eq []
    end

    it 'creates no range for a future sprint that is added and then removed' do
      board.sprints << Sprint.new(
        raw: { 'id' => 3, 'state' => 'future', 'name' => 'Sprint 3',
               'startDate' => '2021-02-01T00:00:00+00:00', 'endDate' => '2021-02-14T00:00:00+00:00' },
        timezone_offset: '+0000'
      )
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: 'Sprint 3', value_id: '3', time: '2021-01-05')
      add_mock_change(
        issue: issue, field: 'Sprint', value: '', value_id: '', old_value: 'Sprint 3', old_value_id: '3',
        time: '2021-01-10'
      )
      expect(chart.collect_sprint_ranges(issue: issue)).to eq []
    end

    it 'ignores a sprint id that is not on the board' do
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: 'Sprint 99', value_id: '99', time: '2021-01-05')
      expect(chart.collect_sprint_ranges(issue: issue)).to eq []
    end

    it 'handles several sprints added and removed in single changes' do
      board.sprints << active_sprint(2, 'Sprint 2', '2021-01-03')
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: 'Sprint 1, Sprint 2', value_id: '1, 2', time: '2021-01-05')
      add_mock_change(
        issue: issue, field: 'Sprint', value: '', value_id: '', old_value: 'Sprint 1, Sprint 2', old_value_id: '1, 2',
        time: '2021-01-10'
      )
      expect(chart.collect_sprint_ranges(issue: issue).collect(&:title)).to contain_exactly('Sprint 1', 'Sprint 2')
    end

    it 'keeps processing removals after one for an un-added sprint' do
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: sprint1.name, value_id: '1', time: '2021-01-05')
      add_mock_change(
        issue: issue, field: 'Sprint', value: '', value_id: '', old_value: 'Gone, Sprint 1', old_value_id: '99, 1',
        time: '2021-01-10'
      )
      # Sprint 1 is still removed at 01-10 (not left open to the flush) despite the earlier un-added 99.
      expect(chart.collect_sprint_ranges(issue: issue)).to eq [
        BarChartRange.new(start: to_time('2021-01-05'), stop: to_time('2021-01-10'),
          color: CssVariable['--sprint-color'], title: 'Sprint 1')
      ]
    end

    it 'keeps adding sprints after one with an unknown id' do
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: 'Gone, Sprint 1', value_id: '99, 1', time: '2021-01-05')
      expect(chart.collect_sprint_ranges(issue: issue).collect(&:title)).to eq ['Sprint 1']
    end

    it 'keeps adding sprints after skipping a future one' do
      board.sprints << Sprint.new(
        raw: { 'id' => 3, 'state' => 'future', 'name' => 'Sprint 3',
               'startDate' => '2021-02-01T00:00:00+00:00', 'endDate' => '2021-02-14T00:00:00+00:00' },
        timezone_offset: '+0000'
      )
      issue = MockIssue.empty created: '2021-01-01', board: board
      add_mock_change(issue: issue, field: 'Sprint', value: 'Sprint 3, Sprint 1', value_id: '3, 1', time: '2021-01-05')
      expect(chart.collect_sprint_ranges(issue: issue).collect(&:title)).to eq ['Sprint 1']
    end
  end
end
