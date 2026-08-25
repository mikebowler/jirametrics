# frozen_string_literal: true

require './spec/spec_helper'

describe ChartBase do
  let(:chart_base) { described_class.new }

  describe '#render_top_text' do
    # Header, description and no-data text all expand the same way. Each gets its own scope, so a
    # template that renders another template cannot clobber the outer one's ERB output buffer.
    it 'expands the header as ERB, the same as the description' do
      chart_base.header_text 'Total: <%= 2 + 2 %>'
      chart_base.description_text 'Also <%= 3 + 3 %>'

      expect(chart_base.render_top_text).to eq "<h1 class='foldable'>Total: 4</h1>Also 6"
    end

    it 'reaches instance variables and methods but not the caller locals' do
      chart_base.header_text 'Days: <%= label_days 2 %>'
      chart_base.description_text ''

      expect(chart_base.render_top_text).to eq "<h1 class='foldable'>Days: 2 days</h1>"
    end
  end

  describe 'seam markers' do
    # Stitch configs select content with grab_by_title, matching the title in the seam comment. That
    # has to be the rendered header, not the template, or a templated header breaks every config
    # that referred to the chart by the name a reader actually sees.
    it 'carries the rendered header, not the raw template' do
      chart_base.header_text 'Total <%= 2 + 2 %>'
      expect(chart_base.seam_start).to include '| Total 4 |'
    end
  end

  describe '#render_no_data' do
    it 'returns nothing at all when no text has been set' do
      expect(chart_base.render_no_data).to eq ''
    end

    it 'returns nothing at all when the text is empty' do
      chart_base.no_data_text ''
      expect(chart_base.render_no_data).to eq ''
    end

    it 'expands the text as ERB, and it can render the header itself' do
      chart_base.header_text 'My Chart'
      chart_base.description_text ''
      chart_base.no_data_text '<%= render_top_text %><div>Nothing to show.</div>'

      expect(chart_base.render_no_data).to eq "<h1 class='foldable'>My Chart</h1><div>Nothing to show.</div>"
    end
  end

  describe '#label_days' do
    it 'is singular for one' do
      expect(chart_base.label_days(1)).to eq '1 day'
    end

    it 'is plural for five' do
      expect(chart_base.label_days(5)).to eq '5 days'
    end

    it "is 'unknown' for a nil count" do
      expect(chart_base.label_days(nil)).to eq 'unknown'
    end
  end

  describe '#label_issues' do
    it 'is singular for one' do
      expect(chart_base.label_issues(1)).to eq '1 issue'
    end

    it 'is plural for five' do
      expect(chart_base.label_issues(5)).to eq '5 issues'
    end
  end

  describe '#daily_chart_dataset' do
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

  describe '#current_board' do
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

  describe '#completed_issues_in_range' do
    let(:board) { load_complete_sample_board }
    let(:issue1) { MockIssue.empty(board: board) }

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

  describe '#stagger_label_positions' do
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

  describe '#normalize_annotation_datetime' do
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

  describe '#date_annotation' do
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
      aggregate_failures do
        expect(result).to include('"2022-06-01T00:00:00+00:00"')
        expect(result).to include('"Coaching started"')
        expect(result).to include('dateAnnotation0:')
        expect(result).to include('position: "5%"')
      end
    end

    it 'staggers labels for close annotations' do
      chart_base.settings = {
        'date_annotations' => [
          { 'date' => '2022-06-01', 'label' => 'First' },
          { 'date' => '2022-06-03', 'label' => 'Second' }
        ]
      }
      result = chart_base.date_annotation
      aggregate_failures do
        expect(result).to include('position: "5%"')
        expect(result).to include('position: "25%"')
      end
    end

    it 'includes annotation for a datetime within range' do
      chart_base.settings = { 'date_annotations' => [{ 'date' => '2022-06-01T10:00:00', 'label' => 'Meeting' }] }
      result = chart_base.date_annotation
      aggregate_failures do
        expect(result).to include('"2022-06-01T10:00:00+00:00"')
        expect(result).to include('dateAnnotation0:')
      end
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
      aggregate_failures do
        expect(result).to include('dateAnnotation0:')
        expect(result).to include('dateAnnotation1:')
      end
    end

    it 'filters out-of-range annotations while keeping in-range ones' do
      chart_base.settings = {
        'date_annotations' => [
          { 'date' => '2021-01-01', 'label' => 'Too early' },
          { 'date' => '2022-06-01', 'label' => 'In range' }
        ]
      }
      result = chart_base.date_annotation
      aggregate_failures do
        expect(result).to include('dateAnnotation0:')
        expect(result).not_to include('dateAnnotation1:')
        expect(result).to include('"In range"')
        expect(result).not_to include('"Too early"')
      end
    end
  end

  describe '#holidays' do
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

    it 'treats a single isolated holiday as a one-day range' do
      chart_base.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-04') # Tue-Fri
      chart_base.holiday_dates = [Date.parse('2022-02-02')] # Wed only
      expect(chart_base.holidays).to eq [Date.parse('2022-02-02')..Date.parse('2022-02-02')]
    end

    it 'includes a non-working run that ends the date range' do
      # Regression: a range ending on a weekend used to be dropped entirely because the run was only
      # flushed when a following working day appeared.
      chart_base.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-06') # Tue-Sun
      chart_base.holiday_dates = []
      expect(chart_base.holidays).to eq [Date.parse('2022-02-05')..Date.parse('2022-02-06')]
    end

    it 'returns a separate range for each non-contiguous run' do
      chart_base.date_range = Date.parse('2022-02-01')..Date.parse('2022-02-14') # ends on a working Monday
      chart_base.holiday_dates = [Date.parse('2022-02-02')] # isolated Wed
      expect(chart_base.holidays).to eq [
        Date.parse('2022-02-02')..Date.parse('2022-02-02'), # the Wed holiday
        Date.parse('2022-02-05')..Date.parse('2022-02-06'), # first weekend
        Date.parse('2022-02-12')..Date.parse('2022-02-13')  # second weekend
      ]
    end
  end

  describe '#percentile_of' do
    # Nearest rank: the smallest value with at least this percentage of the data at or below it.
    it 'returns the value with that share of the data at or below it' do
      values = (1..10).to_a
      aggregate_failures do
        expect(chart_base.percentile_of values, 50).to eq 5
        expect(chart_base.percentile_of values, 85).to eq 9
        expect(chart_base.percentile_of values, 100).to eq 10
        expect(chart_base.percentile_of values, 0).to eq 1
      end
    end

    # The old formula overshot by one whenever size * percentile / 100 came out exact, so the
    # 85th on 100 items reported the 86th value. That is the bug this method exists to fix.
    it 'does not overshoot when the rank lands exactly on a boundary' do
      aggregate_failures do
        expect(chart_base.percentile_of (1..100).to_a, 85).to eq 85
        expect(chart_base.percentile_of (1..20).to_a, 85).to eq 17
        expect(chart_base.percentile_of (1..40).to_a, 85).to eq 34
      end
    end

    it 'is not confused by unsorted input or duplicates' do
      aggregate_failures do
        expect(chart_base.percentile_of [9, 1, 5, 5, 3], 50).to eq 5
        expect(chart_base.percentile_of [5, 5, 5, 5], 85).to eq 5
      end
    end

    it 'returns nil for no values' do
      expect(chart_base.percentile_of [], 85).to be_nil
    end

    it 'returns the only value when there is one' do
      expect(chart_base.percentile_of [7], 50).to eq 7
    end
  end

  # The reason percentile_of exists. Three call sites used to compute percentiles independently,
  # and they disagreed whenever the rank landed exactly on a boundary, so the same percentile of
  # the same data could read differently on the scatterplot and the histogram.
  describe 'percentile agreement across the charts' do
    it 'gives the histogram and the flat-list charts the same answer' do
      values = (1..100).to_a
      histogram_data = values.tally
      histogram = TimeBasedHistogram.new
      aggregate_failures do
        [0, 25, 50, 75, 85, 98, 100].each do |percentile|
          from_list = chart_base.percentile_of values, percentile
          from_histogram = histogram.percentiles_for(histogram_data, [percentile], values.size)[percentile]
          expect(from_histogram).to eq(from_list), "percentile #{percentile} disagreed"
        end
      end
    end
  end

  describe '#comma_and' do
    it 'joins two with and' do
      expect(chart_base.comma_and %w[a b]).to eq 'a and b'
    end

    it 'joins three or more with commas and a final and' do
      expect(chart_base.comma_and %w[a b c]).to eq 'a, b and c'
    end

    it 'returns a single phrase untouched' do
      expect(chart_base.comma_and %w[a]).to eq 'a'
    end
  end

  describe '#ordinal' do
    it 'uses st, nd and rd for the values that need them' do
      aggregate_failures do
        expect(chart_base.ordinal 1).to eq '1st'
        expect(chart_base.ordinal 2).to eq '2nd'
        expect(chart_base.ordinal 3).to eq '3rd'
        expect(chart_base.ordinal 21).to eq '21st'
        expect(chart_base.ordinal 22).to eq '22nd'
        expect(chart_base.ordinal 23).to eq '23rd'
      end
    end

    # The teens are the exception that a naive "look at the last digit" rule gets wrong.
    it 'uses th for the teens' do
      aggregate_failures do
        expect(chart_base.ordinal 11).to eq '11th'
        expect(chart_base.ordinal 12).to eq '12th'
        expect(chart_base.ordinal 13).to eq '13th'
      end
    end

    it 'uses th for everything else' do
      aggregate_failures do
        expect(chart_base.ordinal 0).to eq '0th'
        expect(chart_base.ordinal 50).to eq '50th'
        expect(chart_base.ordinal 85).to eq '85th'
        expect(chart_base.ordinal 100).to eq '100th'
      end
    end
  end

  describe '#format_integer' do
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

  describe '#format_status' do
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

    it 'resolves a ChangeItem to its status via value_id' do
      review = board.possible_statuses.find { |s| s.name == 'Review' }
      change = MockChangeItem.new(
        field: 'status', value: 'Review', value_id: review.id, time: '2021-01-01'
      ).to_change_item
      expect(chart_base.format_status(change, board: board))
        .to eq chart_base.format_status(review, board: board)
    end

    it 'resolves a ChangeItem via old_value_id when use_old_status is set' do
      review = board.possible_statuses.find { |s| s.name == 'Review' }
      change = MockChangeItem.new(
        field: 'status', value: 'New', value_id: 99_999, old_value: 'Review', old_value_id: review.id,
        time: '2021-01-01'
      ).to_change_item
      expect(chart_base.format_status(change, board: board, use_old_status: true))
        .to eq chart_base.format_status(review, board: board)
    end

    it 'renders a red error span with the value when the status id is unknown' do
      change = MockChangeItem.new(
        field: 'status', value: 'Mystery', value_id: 99_999, time: '2021-01-01'
      ).to_change_item
      expect(chart_base.format_status(change, board: board)).to eq "<span style='color: red'>Mystery</span>"
    end

    it 'renders the old value in the error span when use_old_status is set' do
      change = MockChangeItem.new(
        field: 'status', value: 'NewMystery', value_id: 99_999, old_value: 'OldMystery', old_value_id: 88_888,
        time: '2021-01-01'
      ).to_change_item
      expect(chart_base.format_status(change, board: board, use_old_status: true))
        .to eq "<span style='color: red'>OldMystery</span>"
    end

    it 'renders the category and skips the visibility icon when is_category is true' do
      # Backlog is not mapped to any column, so it would normally get the 👀 icon.
      backlog = board.possible_statuses.find { |s| s.name == 'Backlog' }
      expect(chart_base.format_status(backlog, board: board, is_category: true)).to eq(
        "<span title='Category: \"To Do\":2'><div class='color_block' " \
          "style='background: var(--status-category-todo-color);'></div> \"To Do\":2</span>"
      )
    end

    it 'raises for an unexpected object type' do
      expect { chart_base.format_status(42, board: board) }.to raise_error('Unexpected type: Integer')
    end
  end

  describe '#link_to_issue' do
    let(:issue1) { MockIssue.empty(key: 'SP-1') }

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

  # Returns a CssVariable rather than a literal so the colour follows the theme and can be
  # overridden in a user's stylesheet. It is also not random; see ColorPalette.
  it 'hands out a palette slot as a css variable' do
    expect(chart_base.next_palette_color).to eq CssVariable['--palette-color-1']
  end

  it 'moves on to the next slot each time' do
    expect([chart_base.next_palette_color, chart_base.next_palette_color]).to eq [
      CssVariable['--palette-color-1'], CssVariable['--palette-color-2']
    ]
  end

  describe '#to_human_readable' do
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
