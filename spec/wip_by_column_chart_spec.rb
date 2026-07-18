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
    chart.file_system = MockFileSystem.new
    chart.file_system.when_loading(
      file: File.expand_path('./lib/jirametrics/html/wip_by_column_chart.erb'),
      json: :not_mocked
    )
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

  describe '#column_stats' do
    it 'returns one ColumnStats per visible column' do
      chart.issues = []
      expect(chart.column_stats.size).to eq board.visible_columns.size
    end

    it 'populates the column name and wip limits from the board column' do
      chart.issues = []
      stats = chart.column_stats

      aggregate_failures do
        expect(stats[0].name).to eq 'Ready'
        expect(stats[0].min_wip_limit).to eq 1   # Ready min
        expect(stats[0].max_wip_limit).to eq 4   # Ready max
        expect(stats[1].name).to eq 'In Progress'
        expect(stats[1].min_wip_limit).to be_nil # In Progress min
        expect(stats[1].max_wip_limit).to eq 3   # In Progress max
        expect(stats[3].max_wip_limit).to be_nil # Done max
      end
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

      aggregate_failures do
        # Ready: WIP=2 for first 500s, WIP=1 for last 500s
        expect(stats[0].wip_history).to eq [[1, 500], [2, 500]]

        # In Progress: WIP=0 for first 500s, WIP=1 for last 500s
        expect(stats[1].wip_history).to eq [[0, 500], [1, 500]]
      end
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

      aggregate_failures do
        # Ready: WIP=2 for 500s, WIP=0 for 500s
        expect(stats[0].wip_history).to eq [[0, 500], [2, 500]]
        # In Progress: WIP=0 for 500s, WIP=2 for 500s
        expect(stats[1].wip_history).to eq [[0, 500], [2, 500]]
      end
    end
  end

  describe '#within_window?' do
    # chart window is 2021-06-01T00:00:00 .. 2021-06-01T00:16:40
    def within? time
      chart.send(:within_window?, time && to_time(time))
    end

    it 'is falsey for a nil time' do
      expect(within?(nil)).to be_falsey
    end

    it 'excludes the window start, includes just after' do
      aggregate_failures do
        expect(within?('2021-06-01T00:00:00')).to be_falsey
        expect(within?('2021-06-01T00:00:01')).to be_truthy
      end
    end

    it 'includes the window end, excludes just after' do
      aggregate_failures do
        expect(within?('2021-06-01T00:16:40')).to be_truthy
        expect(within?('2021-06-01T00:16:41')).to be_falsey
      end
    end
  end

  describe '#in_wip_and_within_window?' do
    # chart window is 2021-06-01T00:00:00 .. 2021-06-01T00:16:40
    def in_window? time, started:, stopped:
      change = Struct.new(:time).new(to_time(time))
      chart.send(:in_wip_and_within_window?, change, to_time(started), stopped && to_time(stopped))
    end

    it 'excludes a change at the window start, includes one just after' do
      aggregate_failures do
        expect(in_window?('2021-06-01T00:00:00', started: '2021-06-01T00:00:00', stopped: nil)).to be false
        expect(in_window?('2021-06-01T00:00:01', started: '2021-06-01T00:00:00', stopped: nil)).to be true
      end
    end

    it 'includes a change at the window end, excludes one just after' do
      aggregate_failures do
        expect(in_window?('2021-06-01T00:16:40', started: '2021-06-01T00:00:00', stopped: nil)).to be true
        expect(in_window?('2021-06-01T00:16:41', started: '2021-06-01T00:00:00', stopped: nil)).to be false
      end
    end

    it 'includes a change at the start time, excludes one just before' do
      aggregate_failures do
        expect(in_window?('2021-06-01T00:08:20', started: '2021-06-01T00:08:20', stopped: nil)).to be true
        expect(in_window?('2021-06-01T00:08:19', started: '2021-06-01T00:08:20', stopped: nil)).to be false
      end
    end

    it 'excludes a change at or after the stop time, includes one just before' do
      window = { started: '2021-06-01T00:00:00', stopped: '2021-06-01T00:08:20' }
      aggregate_failures do
        expect(in_window?('2021-06-01T00:08:19', **window)).to be true
        expect(in_window?('2021-06-01T00:08:20', **window)).to be false
        expect(in_window?('2021-06-01T00:08:21', **window)).to be false
      end
    end
  end

  describe '#column_as_of' do
    # board status→column map: 10001→0 (Ready), 3→1 (In Progress), 10011→2 (Review)
    let(:status_to_column) { { 10_001 => 0, 3 => 1, 10_011 => 2 } }

    def status_change time, value_id
      Struct.new(:time, :value_id).new(to_time(time), value_id)
    end

    def issue_with *changes
      Struct.new(:status_changes).new(changes)
    end

    def column_as_of issue, time
      chart.send(:column_as_of, issue, to_time(time), status_to_column)
    end

    it 'returns nil when the issue has no status changes' do
      expect(column_as_of(issue_with, '2021-06-01T00:10:00')).to be_nil
    end

    it 'returns nil when every status change is after the given time' do
      issue = issue_with status_change('2021-06-01T00:10:00', 3)
      expect(column_as_of(issue, '2021-06-01T00:05:00')).to be_nil
    end

    it 'includes a change at exactly the given time, excludes one just after' do
      aggregate_failures do
        expect(column_as_of(issue_with(status_change('2021-06-01T00:10:00', 3)), '2021-06-01T00:10:00')).to eq 1
        expect(column_as_of(issue_with(status_change('2021-06-01T00:10:01', 3)), '2021-06-01T00:10:00')).to be_nil
      end
    end

    it 'uses the most recent change at or before the time, not the earliest' do
      issue = issue_with(
        status_change('2021-06-01T00:02:00', 10_001), # Ready, column 0
        status_change('2021-06-01T00:05:00', 3)       # In Progress, column 1
      )
      expect(column_as_of(issue, '2021-06-01T00:10:00')).to eq 1
    end

    it 'maps the change value_id through the column map' do
      aggregate_failures do
        expect(column_as_of(issue_with(status_change('2021-06-01T00:05:00', 10_001)), '2021-06-01T00:10:00')).to eq 0
        expect(column_as_of(issue_with(status_change('2021-06-01T00:05:00', 10_011)), '2021-06-01T00:10:00')).to eq 2
      end
    end
  end

  describe '#compute_wip_seconds' do
    # window is 2021-06-01T00:00:00 .. 00:16:40 = 1000 seconds, across 4 columns. compute_wip_seconds
    # only ever uses an issue as a hash key, so plain symbols stand in for real issues here.
    def compute current_column, events
      timed = events.map { |time, issue, col| [to_time(time), issue, col] }
      chart.send(:compute_wip_seconds, Array.new(4), current_column, timed)
    end

    it 'attributes the whole window to each column at its starting WIP level' do
      result = compute({ a: 0, b: nil }, []) # b is not in WIP, so it is not counted anywhere
      aggregate_failures do
        expect(result).to eq [{ 1 => 1000 }, { 0 => 1000 }, { 0 => 1000 }, { 0 => 1000 }]
        expect(result[0][1]).to be_an(Integer) # integer seconds, from the final stretch
      end
    end

    it 'splits time across the old and new column when an issue moves' do
      result = compute({ a: 0 }, [['2021-06-01T00:06:40', :a, 1]]) # move at the 400s mark
      aggregate_failures do
        expect(result).to eq [{ 1 => 400, 0 => 600 }, { 0 => 400, 1 => 600 }, { 0 => 1000 }, { 0 => 1000 }]
        expect(result[0][1]).to be_an(Integer) # integer seconds, from the in-loop accumulation
      end
    end

    it 'drops the issue out of WIP when it moves to a nil column' do
      result = compute({ a: 0 }, [['2021-06-01T00:06:40', :a, nil]])
      expect(result).to eq [{ 1 => 400, 0 => 600 }, { 0 => 1000 }, { 0 => 1000 }, { 0 => 1000 }]
    end

    it 'tracks an issue moving through several columns in sequence' do
      result = compute({ a: 0 }, [
        ['2021-06-01T00:05:00', :a, 1], # 300s: column 0 -> 1
        ['2021-06-01T00:10:00', :a, 2]  # 600s: column 1 -> 2 (relies on the current_column update)
      ])
      expect(result).to eq [
        { 1 => 300, 0 => 700 },
        { 0 => 700, 1 => 300 },
        { 0 => 600, 1 => 400 },
        { 0 => 1000 }
      ]
    end

    it 'counts multiple issues sharing a column as a higher WIP level' do
      result = compute({ a: 0, b: 0 }, [])
      expect(result).to eq [{ 2 => 1000 }, { 0 => 1000 }, { 0 => 1000 }, { 0 => 1000 }]
    end

    it 'does not advance time for simultaneous events sharing a timestamp' do
      result = compute({ a: 0, b: 0 }, [
        ['2021-06-01T00:06:40', :a, 1], # both at the 400s mark; the second event has zero elapsed
        ['2021-06-01T00:06:40', :b, 1]
      ])
      expect(result).to eq [
        { 2 => 400, 0 => 600 },
        { 0 => 400, 2 => 600 },
        { 0 => 1000 },
        { 0 => 1000 }
      ]
    end

    it 'brings an issue into WIP when it enters from no column (nil old column)' do
      result = compute({ a: nil }, [['2021-06-01T00:06:40', :a, 0]]) # enters column 0 at the 400s mark
      expect(result).to eq [{ 0 => 400, 1 => 600 }, { 0 => 1000 }, { 0 => 1000 }, { 0 => 1000 }]
    end

    it 'adds no final stretch when the last event lands exactly on the window end' do
      result = compute({ a: 0 }, [['2021-06-01T00:16:40', :a, 1]]) # event at the 1000s window end
      expect(result).to eq [{ 1 => 1000 }, { 0 => 1000 }, { 0 => 1000 }, { 0 => 1000 }]
    end
  end

  describe '#accumulate_wip_seconds' do
    def accumulate wip_counts, prev_time, time
      column_wip_seconds = Array.new(wip_counts.size) { Hash.new(0) }
      new_prev = chart.send(
        :accumulate_wip_seconds, column_wip_seconds, wip_counts, to_time(prev_time), to_time(time)
      )
      [column_wip_seconds, new_prev]
    end

    it 'attributes the elapsed seconds to each column at its current WIP level, and returns the new time' do
      column_wip_seconds, new_prev = accumulate([2, 0, 1], '2021-06-01T00:00:00', '2021-06-01T00:06:40')
      aggregate_failures do
        expect(column_wip_seconds).to eq [{ 2 => 400 }, { 0 => 400 }, { 1 => 400 }]
        expect(new_prev).to eq to_time('2021-06-01T00:06:40')
        expect(column_wip_seconds[0][2]).to be_an(Integer) # integer seconds
      end
    end

    it 'changes nothing and keeps the previous time when no time has elapsed' do
      column_wip_seconds, new_prev = accumulate([1], '2021-06-01T00:06:40', '2021-06-01T00:06:40')
      aggregate_failures do
        expect(column_wip_seconds).to eq [{}]
        expect(new_prev).to eq to_time('2021-06-01T00:06:40')
      end
    end
  end

  describe '#apply_event' do
    def apply wip_counts, current_column, issue, new_col
      chart.send(:apply_event, wip_counts, current_column, issue, new_col)
      [wip_counts, current_column]
    end

    it 'moves the issue out of its old column and into the new one' do
      expect(apply([1, 0], { a: 0 }, :a, 1)).to eq [[0, 1], { a: 1 }]
    end

    it 'only increments when the issue enters from a nil column' do
      expect(apply([0, 0], { a: nil }, :a, 0)).to eq [[1, 0], { a: 0 }]
    end

    it 'only decrements when the issue leaves to a nil column' do
      expect(apply([1, 0], { a: 0 }, :a, nil)).to eq [[0, 0], { a: nil }]
    end
  end

  describe '#wip_percentages' do
    it 'pairs each WIP level with its percentage of the column total' do
      result = chart.send(:wip_percentages, [[1, 250], [3, 750]], 1000.0)
      expect(result).to eq [{ 'wip' => 1, 'pct' => 25.0 }, { 'wip' => 3, 'pct' => 75.0 }]
    end

    it 'returns an empty list for an empty history' do
      expect(chart.send(:wip_percentages, [], 1000.0)).to eq []
    end
  end

  describe '#max_wip_level' do
    def stat wip_levels
      WipByColumnChart::ColumnStats.new(wip_history: wip_levels.map { |wip| [wip, 100] })
    end

    it 'returns the highest WIP level reached across every column' do
      # highest level (3) is neither first nor last in the flattened list, to pin it to max
      expect(chart.send(:max_wip_level, [stat([1, 3]), stat([2])])).to eq 3
    end

    it 'returns 0 when no column has any history' do
      expect(chart.send(:max_wip_level, [stat([]), stat([])])).to eq 0
    end
  end

  describe '#wip_limits' do
    def stat min, max
      WipByColumnChart::ColumnStats.new(min_wip_limit: min, max_wip_limit: max)
    end

    it 'maps each column to its min and max WIP limits, in order' do
      result = chart.send(:wip_limits, [stat(1, 4), stat(nil, 3)])
      expect(result).to eq [{ 'min' => 1, 'max' => 4 }, { 'min' => nil, 'max' => 3 }]
    end
  end

  describe '#run' do
    # run's data assembly is normally reachable only through the HTML wrap_and_render produces.
    # Stub that out and we can assert the instance variables run builds directly, with no ERB or
    # binding machinery in play.
    def run_ivars
      allow(chart).to receive(:wrap_and_render).and_return('')
      chart.run
      %i[column_names wip_data max_wip wip_limits recommendations recommendation_texts header_text]
        .to_h { |name| [name, chart.instance_variable_get(:"@#{name}")] }
    end

    before { chart.issues = [issue_in_ready(key: 'SP-1')] } # one issue, in Ready for the whole 1000s window

    it 'builds the per-column data for the board, trimming trailing empty columns' do
      ivars = run_ivars
      aggregate_failures do
        expect(ivars[:header_text]).to eq "WIP by column on board: #{board.name}"
        expect(ivars[:column_names]).to eq ['Ready'] # In Progress/Review/Done are all-zero and trimmed
        expect(ivars[:wip_data]).to eq [[{ 'wip' => 1, 'pct' => 100.0 }]]
        expect(ivars[:max_wip]).to eq 1
        expect(ivars[:wip_limits]).to eq [{ 'min' => 1, 'max' => 4 }]
      end
    end

    it 'produces empty per-column data (and keeps every column) for a zero-length window' do
      chart.time_range = to_time('2021-06-01T00:00:00')..to_time('2021-06-01T00:00:00')
      ivars = run_ivars
      aggregate_failures do
        expect(ivars[:wip_data]).to eq [[], [], [], []] # every column's total time is zero
        expect(ivars[:max_wip]).to eq 0
        expect(ivars[:column_names]).to eq ['Ready', 'In Progress', 'Review', 'Done'] # nothing trimmed
      end
    end

    it 'reports fractional percentages when a column sits at more than one WIP level' do
      issue_b = issue_in_ready key: 'SP-2'
      add_mock_change issue: issue_b, field: 'status',
        value: 'In Progress', value_id: 3,
        time: to_time('2021-06-01T00:06:40') # moves out of Ready at the 400s mark
      chart.issues = [issue_in_ready(key: 'SP-1'), issue_b]

      ivars = run_ivars
      # Ready holds both issues for 400s (WIP 2, 40%) then just one for 600s (WIP 1, 60%)
      expect(ivars[:wip_data][0]).to eq [{ 'wip' => 1, 'pct' => 60.0 }, { 'wip' => 2, 'pct' => 40.0 }]
    end

    it 'leaves recommendations empty unless they are enabled' do
      ivars = run_ivars
      aggregate_failures do
        expect(ivars[:recommendations]).to eq [nil]
        expect(ivars[:recommendation_texts]).to eq []
      end
    end

    it 'computes recommendations and their texts when enabled' do
      chart.show_recommendations
      ivars = run_ivars
      aggregate_failures do
        expect(ivars[:recommendations]).to eq [1]
        expect(ivars[:recommendation_texts]).to eq ["Lower the WIP limit for 'Ready' from 4 to 1"]
      end
    end
  end

  describe '#show_recommendations' do
    context 'with two issues (one stays in Ready, one moves to In Progress after 400s)' do
      # Window is 1000s. Issue A stays in Ready the whole time (1000s at WIP=1).
      # Issue B is in Ready for 600s then moves to In Progress for 400s.
      # Ready column: WIP=1 for 400s (40%), WIP=2 for 600s (60%) — total 1000s
      #   sorted: [[1,400],[2,600]]
      #   cumulative: WIP=1 → 400/1000=40%, WIP=2 → 1000/1000=100%
      #   85th percentile lands at WIP=2  → recommended max = 2
      # In Progress: WIP=0 for 600s, WIP=1 for 400s
      #   85th percentile → cumulative WIP=0: 60%, WIP=1: 100% → recommended = 1
      before do
        issue_a = issue_in_ready key: 'SP-1' # stays in Ready all 1000s

        issue_b = issue_in_ready key: 'SP-2'
        add_mock_change issue: issue_b, field: 'status',
          value: 'In Progress', value_id: 3,
          time: to_time('2021-06-01T00:06:40') # 400s in
        chart.issues = [issue_a, issue_b]
      end

      it 'recommendations are not shown by default' do
        output = chart.run
        aggregate_failures do
          expect(output).not_to include('rec: ')
          expect(output).not_to include('WIP limit recommendations')
        end
      end

      it 'computes the 85th-percentile WIP per column' do
        stats = chart.column_stats

        recs = chart.send(:compute_recommendations, stats)

        aggregate_failures do
          # Ready: WIP=1 for 400s (40%), WIP=2 for 600s (60%); 85% reached at WIP=2
          expect(recs[0]).to eq 2
          # In Progress: WIP=0 for 600s (60%), WIP=1 for 400s (40%); 85% reached at WIP=1
          expect(recs[1]).to eq 1
        end
      end

      it 'draws recommendation lines and texts when enabled' do
        chart.show_recommendations
        output = chart.run

        aggregate_failures do
          expect(output).to include('rec: ')
          expect(output).to include('WIP limit recommendations')
        end
      end

      it 'suggests adding a limit when none exists' do
        chart.show_recommendations
        output = chart.run

        aggregate_failures do
          # In Progress has max=3 so rec=1 < 3 → lower; Ready has max=4 so rec=2 < 4 → lower
          # Done has no non-zero WIP so it's trimmed
          expect(output).to include("Lower the WIP limit for 'Ready' from 4 to 2")
          expect(output).to include("Lower the WIP limit for 'In Progress' from 3 to 1")
        end
      end
    end

    it 'recommends removing a column when 85% of time is at WIP=0' do
      # Issue passes through In Progress briefly (100s) but Ready is empty for 900s
      # Ready: WIP=0 for 900s (90%), WIP=1 for 100s (10%) → 85th pct at WIP=0
      issue = issue_in_ready key: 'SP-1'
      add_mock_change issue: issue, field: 'status',
        value: 'In Progress', value_id: 3,
        time: to_time('2021-06-01T00:15:20') # 920s into the 1000s window

      chart.issues = [issue]
      chart.show_recommendations
      output = chart.run

      aggregate_failures do
        expect(output).to include("Almost nothing passes through column 'In Progress'")
        expect(output).not_to include("Lower the WIP limit for 'In Progress'")
        expect(output).not_to include("Add a WIP limit to column 'In Progress'")
      end
    end

    it 'suggests adding a limit when there is no existing limit' do
      # Done has min=nil, max=nil — use mock cycletime so the issue counts as in-WIP
      issue = empty_issue created: '2021-05-31', board: board, key: 'SP-1'
      add_mock_change issue: issue, field: 'status',
        value: 'Done', value_id: 10_002,
        time: to_time('2021-05-31T12:00:00')
      board.cycletime = mock_cycletime_config stub_values: [
        ['SP-1', '2021-05-31T12:00:00', nil]
      ]

      chart.issues = [issue]
      chart.show_recommendations
      output = chart.run

      expect(output).to include("Add a WIP limit to column 'Done'")
    end
  end

  describe '#trim_zero_end_columns' do
    it 'removes a leading all-zero column' do
      # Issue is only in In Progress — Ready (index 0) stays at WIP=0 the whole window
      issue = empty_issue created: '2021-05-31', board: board, key: 'SP-1'
      add_mock_change issue: issue, field: 'status',
        value: 'In Progress', value_id: 3,
        time: to_time('2021-05-31T12:00:00')

      chart.issues = [issue]
      output = chart.run

      aggregate_failures do
        expect(output).not_to include('"Ready"')
        expect(output).to include('"In Progress"')
      end
    end

    it 'removes a trailing all-zero column' do
      # Issue stays in Ready the whole window — Done (index 3) stays at WIP=0
      issue = issue_in_ready key: 'SP-1'

      chart.issues = [issue]
      output = chart.run

      aggregate_failures do
        expect(output).not_to include('"Done"')
        expect(output).to include('"Ready"')
      end
    end

    it 'keeps an all-zero column in the middle' do
      # Issues in Ready and Review but nothing in In Progress (index 1)
      issue_a = issue_in_ready key: 'SP-1'

      issue_b = empty_issue created: '2021-05-31', board: board, key: 'SP-2'
      add_mock_change issue: issue_b, field: 'status',
        value: 'Review', value_id: 10_011,
        time: to_time('2021-05-31T12:00:00')

      chart.issues = [issue_a, issue_b]
      output = chart.run

      aggregate_failures do
        expect(output).to include('"Ready"')
        expect(output).to include('"In Progress"')
        expect(output).to include('"Review"')
        expect(output).not_to include('"Done"')
      end
    end
  end

  context 'with started and stopped times from the cycletime config' do
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
