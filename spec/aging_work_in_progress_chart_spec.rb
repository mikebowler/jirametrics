# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkInProgressChart do
  let(:today) { to_date('2021-06-28') }

  let(:board) do
    load_complete_sample_board.tap do |board|
      board.cycletime = default_cycletime_config
    end
  end
  let :chart do
    issues = load_complete_sample_issues board: board

    # None of the sample issues are complete so we need to add one complete item in order for the 85% line to work.
    issues << create_issue_from_aging_data(
      board: board, ages_by_column: [1, 2, 3, 7], today: today.to_s, key: 'SP-100'
    )
    issues.last.changes << mock_change(field: 'resolution', time: to_time(today.to_s), value: 'done')

    build_chart board: board, issues: issues, show_all_columns: true
  end

  def build_chart board:, issues:, show_all_columns: false
    chart = described_class.new(empty_config_block)
    chart.file_system = MockFileSystem.new
    html_path = File.expand_path('./lib/jirametrics/html/')
    chart.file_system.when_loading(
      file: "#{html_path}/aging_work_in_progress_chart.erb",
      json: :not_mocked
    )
    chart.board_id = 1
    chart.all_boards = { 1 => board }
    chart.issues = issues
    chart.date_range = to_date('2021-06-18')..today
    chart.percentiles 85 => '--aging-work-in-progress-chart-shading-color'
    chart.show_all_columns if show_all_columns
    chart
  end

  describe '#run' do
    # run assembles the chart into locals and ivars that only the ERB template ever reads. Stub the
    # render out, capture the binding run hands it, and the assertions see exactly what the template
    # would, without dragging ERB into the test.
    def rendered chart
      captured_binding = nil
      allow(chart).to receive(:wrap_and_render) { |render_binding, _file| captured_binding = render_binding }
      chart.run
      {
        data_sets: captured_binding.eval('data_sets'),
        max_age: captured_binding.eval('@max_age')
      }
    end

    # Five completed items, enough that 50%, 85% and 100% land on three different ones rather than
    # collapsing onto the same element. Across Ready, In Progress, Review, Done that gives
    # 50% => [3, 7, 14, 23], 85% => [4, 11, 22, 37] and 100% => [6, 17, 34, 57].
    def completed_issues
      ages_by_column = [[1, 2, 3, 7], [2, 4, 6, 8], [3, 5, 8, 10], [4, 8, 12, 16], [6, 12, 18, 24]]
      ages_by_column.each_with_index.collect do |ages, index|
        issue = create_issue_from_aging_data(
          board: board, ages_by_column: ages, today: today.to_s, key: "SP-#{100 + index}"
        )
        issue.changes << mock_change(field: 'resolution', time: to_time(today.to_s), value: 'done')
        issue
      end
    end

    # One item still in flight, sitting in In Progress, 11 days old on the day we render.
    def aging_issue
      MockIssue.empty(board: board, key: 'SP-300').tap do |issue|
        issue.status = board.possible_statuses.find_by_id board.visible_columns[1].status_ids.min
        add_mock_change(
          issue: issue, field: 'status', value: issue.status.name, value_id: issue.status.id,
          time: to_time('2021-06-18')
        )
      end
    end

    def banded_chart show_all_columns: true
      build_chart(board: board, issues: completed_issues + [aging_issue], show_all_columns: show_all_columns)
        .tap { |chart| chart.percentiles 50 => '--fifty-color', 85 => '--eighty-five-color', 100 => '--hundred-color' }
    end

    it 'draws each percentile as a band from the previous percentile age up to its own' do
      bands = rendered(banded_chart)[:data_sets].select { |set| set['type'] == 'bar' }

      expect(bands.collect { |set| [set['label'], set['data']] }).to eq [
        ['50%', [[0, 3], [0, 7], [0, 14], [0, 23]]],
        ['85%', [[3, 4], [7, 11], [14, 22], [23, 37]]],
        ['100%', [[4, 6], [11, 17], [22, 34], [37, 57]]]
      ]
    end

    it 'lifts the ceiling above the tallest band and not just the oldest item' do
      # The oldest item on the board is 11 days but the 100% band reaches 57, so a ceiling based on
      # the items alone would cut the band off at the top of the plot.
      expect(rendered(banded_chart)[:max_age]).to eq 57
    end

    it 'ignores columns that were trimmed away when lifting the ceiling' do
      # Done gets trimmed here, so its band, the tallest on the board, must not set the ceiling.
      # Otherwise there is empty space at the top that no visible bar accounts for.
      expect(rendered(banded_chart(show_all_columns: false))[:max_age]).to eq 34
    end
  end

  describe '#column_for' do
    it 'returns name' do
      chart.run

      # The last issue is the fake 'done' that we inserted so look at the one before that.
      actual = chart.column_for(issue: chart.issues[-2]).name
      expect(actual).to eq 'Review'
    end
  end

  it 'make_data_sets' do
    chart.run

    expect(chart.make_data_sets).to eq([
      {
        'backgroundColor' => CssVariable['--type-story-color'],
        'data' => [
          {
            'title' => ['SP-11 : Report of all orders for an event (11 days)'],
            'x' => 'Ready',
            'y' => 11
          },
          {
            'title' => ['SP-8 : Refund ticket for individual order (11 days)'],
             'x' => 'In Progress',
             'y' => 11
          },
          {
            'title' => ['SP-7 : Purchase ticket with Apple Pay (11 days)'],
             'x' => 'Ready',
             'y' => 11
          },
          {
            'title' => ['SP-2 : Update existing event (11 days)'],
             'x' => 'Ready',
             'y' => 11
          },
          {
            'title' => ['SP-1 : Create new draft event (11 days)'],
            'x' => 'Review',
            'y' => 11
          }
        ],
       'fill' => false,
       'label' => 'Story',
       'showLine' => false,
       'type' => 'line'
     },
     {
       'barPercentage' => 1.0,
       'categoryPercentage' => 1.0,
       'data' => [[0, 1], [0, 2], [0, 4], [0, 10]],
       'label' => '85%',
       'backgroundColor' => CssVariable['--aging-work-in-progress-chart-shading-color'],
       'type' => 'bar'
     }
    ])
  end

  context 'with an extra column for unmapped statuses' do
    it 'shows the column when an issue is present with that status' do
      chart.time_range = to_time('2021-10-01')..to_time('2021-10-30')
      issue = MockIssue.empty board: board
      issue.raw['fields']['status'] = {
        'name' => 'FakeBacklog',
        'id' => '10012',
        'statusCategory' => {
          'name' => 'To Do',
          'id' => '2',
          'key' => 'new'
        }
      }
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2021-10-02', nil]
      ]
      chart.issues << issue
      chart.run

      actual = chart.board_columns.collect do |column|
        "#{column.name}: #{column.status_ids.join(',')}"
      end
      expect(actual).to eq [
        'Ready: 10001',
        'In Progress: 3',
        'Review: 10011',
        'Done: 10002',
        '[Unmapped Statuses]: 10000,10012'
      ]
    end

    it 'hides the column when no issues are in that status' do
      chart.run

      actual = chart.board_columns.collect do |column|
        "#{column.name}: #{column.status_ids.join(',')}"
      end
      expect(actual).to eq [
        'Ready: 10001',
        'In Progress: 3',
        'Review: 10011',
        'Done: 10002'
        # Unmapped status column would be here. Verify it's missing
      ]
    end
  end

  context 'when show_all_columns is false (default)' do
    it 'removes a trailing done column with age data when @fake_column is also visible' do
      # Regression test for the case where Done has non-zero age data (a completed issue
      # passed through it), so indexes_of_leading_and_trailing_zeros never flagged it. With
      # @fake_column also present it is not a trailing zero from age_data's perspective, so it
      # previously stayed.
      completed = create_issue_from_aging_data(
        board: board, ages_by_column: [0, 2, 3, 7], today: '2021-06-28', key: 'SP-200'
      )
      active = MockIssue.empty board: board, key: 'SP-201'
      active.raw['fields']['status'] = {
        'name' => 'FakeBacklog', 'id' => '10012',
        'statusCategory' => { 'name' => 'To Do', 'id' => '2', 'key' => 'new' }
      }
      board.cycletime = mock_cycletime_config stub_values: [
        [completed, '2021-06-15', '2021-06-26'],
        [active,    '2021-06-20', nil]
      ]

      chart = build_chart board: board, issues: [completed, active]
      chart.run

      names = chart.board_columns.map(&:name)
      aggregate_failures do
        expect(names).to include('[Unmapped Statuses]')
        expect(names).not_to include('Done')
      end
    end

    it 'keeps intermediate columns with completion history even when no aging items are currently there' do
      # Regression test for the case where Done is the last visible column: BoardMovementCalculator
      # uses today as end_date for the last column, so Done's age_data is always inflated - it can
      # never be a trailing zero, and the naive algorithm therefore could not remove it. Excluding
      # the last visible column from the age_data right-boundary calculation keeps In Progress and
      # Review while dropping Done.
      # Setup: completed issue passes through In Progress/Review/Done; active issue sits in
      # @fake_column to trigger the scenario.
      completed = create_issue_from_aging_data(
        board: board, ages_by_column: [0, 2, 3, 7], today: '2021-06-28', key: 'SP-200'
      )
      active = MockIssue.empty board: board, key: 'SP-201'
      active.raw['fields']['status'] = {
        'name' => 'FakeBacklog', 'id' => '10012',
        'statusCategory' => { 'name' => 'To Do', 'id' => '2', 'key' => 'new' }
      }
      board.cycletime = mock_cycletime_config stub_values: [
        [completed, '2021-06-15', '2021-06-27'],
        [active,    '2021-06-20', nil]
      ]

      chart = build_chart board: board, issues: [completed, active]
      chart.run

      names = chart.board_columns.map(&:name)
      aggregate_failures do
        expect(names).to include('In Progress')
        expect(names).to include('Review')
        expect(names).to include('[Unmapped Statuses]')
        expect(names).not_to include('Done')
      end
    end

    it 'keeps columns that have active aging items even when they have no historical data' do
      # Board columns: [Ready, In Progress, Review, Done]
      # Completed issue skips Ready -> Ready has zero historical data
      # Active issue IS in Ready -> Ready must still appear first, not last
      completed_issue = create_issue_from_aging_data(
        board: board, ages_by_column: [0, 2, 3, 7], today: today.to_s, key: 'SP-200'
      )
      active_issue = create_issue_from_aging_data(
        board: board, ages_by_column: [5], today: today.to_s, key: 'SP-201'
      )
      board.cycletime = mock_cycletime_config stub_values: [
        [completed_issue, '2021-06-15', '2021-06-26'],
        [active_issue, '2021-06-23', nil]
      ]

      # show_all_columns defaults to false, so leading/trailing zero trimming is active
      chart = build_chart board: board, issues: [completed_issue, active_issue]

      chart.run

      expect(chart.board_columns.first.name).to eq 'Ready'
    end
  end

  describe '#indexes_of_leading_and_trailing_zeros' do
    it 'handles empty' do
      expect(chart.indexes_of_leading_and_trailing_zeros []).to be_empty
    end

    it 'handles all zeros' do
      expect(chart.indexes_of_leading_and_trailing_zeros [0, 0]).to eq [0, 1]
    end

    it 'handles leading and trailing zeros' do
      expect(chart.indexes_of_leading_and_trailing_zeros [0, 0, 5, 0]).to eq [0, 1, 3]
    end

    it 'handles no zeros' do
      expect(chart.indexes_of_leading_and_trailing_zeros [5, 5, 5]).to be_empty
    end

    it 'ignore zero in the middle' do
      expect(chart.indexes_of_leading_and_trailing_zeros [2, 0, 5, 0]).to eq [3]
    end
  end

  describe '#aging_issue_on_board?' do
    it 'includes an in-progress issue on this board' do
      issue = create_issue_from_aging_data(board: board, ages_by_column: [1, 2, 3, 7], today: today.to_s, key: 'SP-200')
      expect(chart.aging_issue_on_board?(issue)).to be true
    end

    it 'excludes an in-progress issue that belongs to a different board' do
      other_board = load_complete_sample_board.tap do |b|
        b.raw['id'] = 2
        b.cycletime = default_cycletime_config
      end
      issue = create_issue_from_aging_data(
        board: other_board, ages_by_column: [1, 2, 3, 7], today: today.to_s, key: 'SP-201'
      )
      expect(chart.aging_issue_on_board?(issue)).to be false
    end
  end

  describe '#aging_datapoints' do
    it 'skips an issue that is not mapped to any column' do
      kept = create_issue_from_aging_data(board: board, ages_by_column: [1, 2, 3, 7], today: today.to_s, key: 'SP-300')
      dropped = create_issue_from_aging_data(
        board: board, ages_by_column: [1, 2, 3, 7], today: today.to_s, key: 'SP-301'
      )
      column = board.visible_columns.first
      allow(chart).to receive(:column_for).with(issue: kept).and_return(column)
      allow(chart).to receive(:column_for).with(issue: dropped).and_return(nil)

      expect(chart.aging_datapoints([kept, dropped]).collect { |point| point['x'] }).to eq [column.name]
    end
  end

  describe '#trim_board_columns' do
    # Columns are Ready(0), In Progress(1), Review(2), Done(3), [Unmapped](4, the fake last one).
    let(:trim_chart) do
      build_chart(board: board, issues: []).tap(&:determine_board_columns)
    end

    def data_sets_for *column_names
      [{ 'data' => column_names.map { |name| { 'x' => name, 'y' => 5 } } }]
    end

    def calculator_with age_data
      instance_double(BoardMovementCalculator).tap do |calc|
        allow(calc).to receive(:age_data_for).and_return(age_data)
      end
    end

    it 'removes nothing and returns [] when showing all columns' do
      trim_chart.show_all_columns
      expect(trim_chart.trim_board_columns(data_sets: [], calculator: calculator_with([]))).to eq []
    end

    it 'trims the columns with no aging items on either side of the ones that have them' do
      result = trim_chart.trim_board_columns(
        data_sets: data_sets_for('In Progress'), calculator: calculator_with([0, 0, 0, 0])
      )
      aggregate_failures do
        expect(result).to eq [0, 2, 3]
        expect(trim_chart.board_columns.map(&:name)).to eq ['In Progress', '[Unmapped Statuses]']
      end
    end

    it 'removes every real column when nothing is aging and there is no history' do
      result = trim_chart.trim_board_columns(data_sets: data_sets_for, calculator: calculator_with([0, 0, 0, 0]))
      aggregate_failures do
        expect(result).to eq [0, 1, 2, 3]
        expect(trim_chart.board_columns.map(&:name)).to eq ['[Unmapped Statuses]']
      end
    end

    it 'keeps the whole span between the first and last aging columns' do
      result = trim_chart.trim_board_columns(
        data_sets: data_sets_for('Ready', 'Review'), calculator: calculator_with([0, 0, 0, 0])
      )
      expect(result).to eq [3] # only Done, past the last aging column, is trimmed
    end

    it 'extends the kept range to columns that have historical age data' do
      result = trim_chart.trim_board_columns(
        data_sets: data_sets_for('Review'), calculator: calculator_with([7, 0, 0, 0])
      )
      expect(result).to eq [3] # Ready is kept via its history even with no current aging item
    end

    it 'ignores history in the last visible column when finding the right boundary' do
      result = trim_chart.trim_board_columns(
        data_sets: data_sets_for('In Progress'), calculator: calculator_with([0, 0, 0, 9])
      )
      expect(result).to eq [0, 2, 3] # Done's inflated history does not keep it
    end

    it 'extends the right boundary to a middle column that has history but no current aging' do
      # Aging only in Ready(0), but history in Review(2) keeps everything up to Review.
      result = trim_chart.trim_board_columns(
        data_sets: data_sets_for('Ready'), calculator: calculator_with([0, 0, 5, 0])
      )
      expect(result).to eq [3] # only Done is trimmed; Review is kept by its history
    end

    it 'ignores non-hash data points when collecting the aging columns' do
      data_sets = [{ 'data' => [{ 'x' => 'In Progress', 'y' => 5 }, [99, 5]] }] # a bar-style array point
      result = trim_chart.trim_board_columns(data_sets: data_sets, calculator: calculator_with([0, 0, 0, 0]))
      expect(result).to eq [0, 2, 3]
    end

    it 'keeps just the single column that has aging items' do
      result = trim_chart.trim_board_columns(
        data_sets: data_sets_for('Ready'), calculator: calculator_with([0, 0, 0, 0])
      )
      aggregate_failures do
        expect(result).to eq [1, 2, 3]
        expect(trim_chart.board_columns.map(&:name)).to eq ['Ready', '[Unmapped Statuses]']
      end
    end

    it 'removes every real column when only the last one has history and nothing is aging' do
      # first_data is set (the last column) but there is no right boundary, so no range can be formed.
      result = trim_chart.trim_board_columns(data_sets: data_sets_for, calculator: calculator_with([0, 0, 0, 9]))
      expect(result).to eq [0, 1, 2, 3]
    end
  end
end
