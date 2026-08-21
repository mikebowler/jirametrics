# frozen_string_literal: true

require './spec/spec_helper'

describe FlowEfficiencyScatterplot do
  let(:board) do
    load_complete_sample_board.tap do |board|
      # Stalled is switched off so that flagged time is the only thing moving flow efficiency, which
      # makes every fixture below exactly (total - blocked) / total.
      board.project_config.settings['stalled_threshold_days'] = 5000
      board.project_config.settings['flagged_means_blocked'] = true
    end
  end

  let(:chart) do
    described_class.new(empty_config_block).tap do |chart|
      chart.file_system = MockFileSystem.new
      html_path = File.expand_path('./lib/jirametrics/html/')
      chart.file_system.when_loading file: "#{html_path}/flow_efficiency_scatterplot.erb", json: :not_mocked
      chart.all_boards = { 1 => board }
      chart.board_id = 1
      chart.date_range = to_date('2021-01-01')..to_date('2021-12-31')
      chart.time_range = to_time('2021-01-01')..to_time('2021-12-31')
      chart.settings = board.project_config.settings
      chart.holiday_dates = []
      chart.issues = []
    end
  end

  # Each item lives for total_days and is flagged, so not adding value, for blocked_days of them,
  # giving a flow efficiency of exactly (total - blocked) / total.
  # Every item has to be registered in ONE mock_cycletime_config: building them one at a time
  # replaces the board's config each call, leaving all but the last with no start or stop time at
  # all, which quietly sends them down the divide-by-zero path and reports them as 0%.
  def use_items *specs
    start = to_date '2021-03-01'
    stubs = []

    chart.issues = specs.each_with_index.collect do |spec, index|
      issue = empty_issue created: start.to_s, board: board, key: "SP-#{index + 1}"
      if spec[:blocked].positive?
        add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked', time: to_time((start + 1).to_s))
        add_mock_change(
          issue: issue, field: 'Flagged', value: '', time: to_time((start + 1 + spec[:blocked]).to_s)
        )
      end
      stubs << [issue, to_time(start.to_s), to_time((start + spec[:total]).to_s)]
      issue
    end

    board.cycletime = mock_cycletime_config stub_values: stubs
  end

  describe '#histogram_buckets' do
    it 'is empty across the whole range when there is nothing to count' do
      counts = chart.histogram_buckets([]).collect { |bucket| bucket['y'] }
      expect(counts).to eq Array.new(20, 0)
    end

    it 'plots each bar at the centre of the band it counts' do
      centres = chart.histogram_buckets([]).collect { |bucket| bucket['x'] }
      expect(centres.first(4)).to eq [2.5, 7.5, 12.5, 17.5]
    end

    it 'counts an item into the band that contains it' do
      buckets = chart.histogram_buckets [1.0, 4.9, 5.0, 7.0, 99.0]
      expect(buckets.collect { |bucket| bucket['y'] }.first(3)).to eq [2, 2, 0]
    end

    it 'keeps a perfect 100% inside the top band rather than dropping it' do
      # 100 is the only value that can land exactly on the upper edge of the last band, so an
      # exclusive comparison silently loses the one item the reader is most likely to look for.
      expect(chart.histogram_buckets([100.0]).last['y']).to eq 1
    end
  end

  describe '#run' do
    def rendered
      captured_binding = nil
      allow(chart).to receive(:wrap_and_render) { |render_binding, _file| captured_binding = render_binding }
      chart.run
      {
        buckets: captured_binding.eval('@buckets'),
        markers: captured_binding.eval('@percentile_markers'),
        median: captured_binding.eval('@median'),
        above_band: captured_binding.eval('@above_band'),
        item_count: captured_binding.eval('@item_count')
      }
    end

    it 'says so when nothing matched rather than rendering an empty chart' do
      expect(chart.run).to include 'No data matched the selected criteria'
    end

    it 'counts the completed items into their bands' do
      use_items({ total: 100, blocked: 96 }, { total: 100, blocked: 94 }, { total: 100, blocked: 88 })
      counts = rendered[:buckets].collect { |bucket| bucket['y'] }
      expect(counts.first(4)).to eq [1, 1, 1, 0]
    end

    it 'draws a line at each configured percentile' do
      use_items({ total: 100, blocked: 96 }, { total: 100, blocked: 80 }, { total: 100, blocked: 60 })
      chart.percentiles [50, 85]
      expect(rendered[:markers]).to eq [
        { 'percentile' => 50, 'value' => 20.0, 'label' => '50% of items are below 20.0%' },
        { 'percentile' => 85, 'value' => 40.0, 'label' => '85% of items are below 40.0%' }
      ]
    end

    it 'counts the items that report spending more than half their life being worked on' do
      # These are the ones that make the chart read as praise, so the template needs the count in
      # order to say what a figure that high actually means.
      use_items({ total: 100, blocked: 96 }, { total: 100, blocked: 40 }, { total: 100, blocked: 10 })
      expect(rendered[:above_band]).to eq 2
    end

    it 'stays quiet when nothing lands above the band' do
      use_items({ total: 100, blocked: 96 })
      expect(rendered[:above_band]).to be_zero
    end

    it 'warns about the one item that reports being worked on most of its life' do
      use_items({ total: 100, blocked: 96 }, { total: 100, blocked: 10 })
      rendered
      expect(chart.band_warning).to include 'One of your work items reports spending more than 50% of its life'
    end

    it 'keeps the warning readable when several items report it' do
      use_items({ total: 100, blocked: 40 }, { total: 100, blocked: 10 })
      rendered
      expect(chart.band_warning).to include '2 of your work items report spending more than 50% of their life'
    end

    it 'says nothing at all when no item lands above the band' do
      use_items({ total: 100, blocked: 96 })
      rendered
      expect(chart.band_warning).to be_empty
    end

    it 'treats an item with no elapsed time as 0% rather than taking the whole report down' do
      # Shouldn't happen on a well configured board, but it has been seen in production.
      use_items({ total: 0, blocked: 0 })
      expect(rendered[:buckets].first['y']).to eq 1
    end

    it 'logs the item it could not divide, so the misconfiguration is findable' do
      use_items({ total: 0, blocked: 0 })
      rendered
      expect(chart.file_system.log_messages).to eq(
        ['Issue(SP-1) flow_efficiency: NaN, active_time: 0.0, total_time: 0.0']
      )
    end
  end
end
