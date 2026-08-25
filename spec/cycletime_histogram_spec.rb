# frozen_string_literal: true

require './spec/spec_helper'

describe CycletimeHistogram do
  let(:board) { load_complete_sample_board }
  let(:issue1) { MockIssue.empty key: 'SP-1', board: board }
  let(:issue2) { MockIssue.empty key: 'SP-2', board: board }
  let(:issue10) { load_issue 'SP-10', board: board }
  let(:chart) { described_class.new(empty_config_block) }

  describe '#cycletime_unit' do
    it 'accepts :days (the only supported unit)' do
      expect { chart.cycletime_unit :days }.not_to raise_error
    end

    it 'raises NotImplementedError for any other unit' do
      expect { chart.cycletime_unit :hours }.to raise_error(
        NotImplementedError, /CycletimeHistogram only supports :days/
      )
    end
  end

  # The percentile lines carried label: { enabled: true }, which is the v1 plugin option. Under
  # the v3 plugin that is a no-op and the label defaults to display: false, so those markers had
  # been silently invisible. They are hover revealed now, matching the scatterplot.
  describe 'percentile line annotations' do
    let(:rendered) do
      chart.file_system = MockFileSystem.new
      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/time_based_histogram.erb'), json: :not_mocked
      )
      board.cycletime = default_cycletime_config
      chart.holiday_dates = []
      chart.settings = load_settings
      chart.time_range = to_time('2021-01-01')..to_time('2022-12-31')
      chart.date_range = Date.parse('2021-01-01')..Date.parse('2022-12-31')
      chart.issues = [issue10]
      chart.run
    end

    it 'uses the option name the installed plugin actually reads' do
      aggregate_failures do
        expect(rendered).to include 'display: false'
        expect(rendered).not_to include 'enabled: true'
      end
    end

    it 'reveals the label on hover with a hit area big enough to reach' do
      aggregate_failures do
        expect(rendered).to include 'hitTolerance: 6'
        expect(rendered).to include 'enter(ctx)'
        expect(rendered).to include 'leave(ctx)'
      end
    end

    it 'names the percentile and its value in the label' do
      expect(rendered).to match(/content: "\d+\w\w percentile at \d+ days?"/)
    end
  end

  # An item that finished before it started has a cycletime of zero or less, so the histogram
  # drops it. A group where that happens to every item survives the grouping but ends up with no
  # data at all, which used to take the entire report down with "can't convert nil into Float"
  # when the stats table tried to format an average that was never calculated. See issue 79.
  describe 'statistics table for a group with no usable data' do
    let(:chart) do
      described_class.new(lambda do |_|
        grouping_rules do |issue, rule|
          rule.label = issue.key == 'SP-1' ? 'Backwards' : 'Forwards'
        end
      end)
    end

    let(:rendered) do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2021-10-10', '2021-10-08'],
        [issue2, '2021-10-01', '2021-10-04']
      ]
      render_with [issue1, issue2]
    end

    def render_with issues
      chart.file_system = MockFileSystem.new
      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/time_based_histogram.erb'), json: :not_mocked
      )
      chart.holiday_dates = []
      chart.settings = load_settings
      chart.time_range = to_time('2021-01-01')..to_time('2022-12-31')
      chart.date_range = Date.parse('2021-01-01')..Date.parse('2022-12-31')
      chart.issues = issues
      chart.run
    end

    # The cells of one row of the statistics table, excluding the label in the first column.
    def stats_row rendered, label
      row = rendered[%r{<tr>\s*<td>#{label}</td>(.*?)</tr>}m, 1]
      row.scan(%r{<td[^>]*>(.*?)</td>}m).flatten.collect(&:strip)
    end

    it 'dashes every column rather than dropping the row' do
      expect(stats_row rendered, 'Backwards').to eq(['&ndash;'] * 7)
    end

    it 'leaves the groups that do have data alone' do
      expect(stats_row rendered, 'Forwards').to eq(%w[4 4 4.00 4 4 4 4])
    end

    it 'explains the dash in a footnote' do
      expect(rendered).to include 'no usable data for that group'
    end

    it 'drops the footnote when every group has data' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue2, '2021-10-01', '2021-10-04']
      ]
      expect(render_with([issue2])).not_to include 'no usable data for that group'
    end
  end

  describe '#histogram_data_for' do
    it 'handles no issues' do
      expect(chart.histogram_data_for items: []).to be_empty
    end

    it 'handles a mix of issues' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2022-01-01', '2022-01-04'],
        [issue2, '2022-01-01', '2022-01-04'],
        [issue10, '2022-01-01', '2022-01-01T01:00:00']
      ]
      expect(chart.histogram_data_for items: [issue1, issue2, issue10]).to eq({ 4 => [issue1, issue2], 1 => [issue10] })
    end
  end

  describe '#data_set_for' do
    it 'handles no data' do
      expect(chart.data_set_for histogram_data: {}, label: 'foo', color: 'red').to eq({
        backgroundColor: 'red',
        borderRadius: 0,
        data: [],
        label: 'foo',
        type: 'bar'
      })
    end

    it 'handles simple data' do
      board.cycletime = default_cycletime_config
      result = chart.data_set_for histogram_data: { 4 => [issue1, issue2], 3 => [] }, label: 'foo', color: 'red'
      expect(result).to eq({
        backgroundColor: 'red',
        borderRadius: 0,
        data: [
          {
            title: [
              '2 items completed in 4 days',
              "#{issue1.key} : #{issue1.summary}",
              "#{issue2.key} : #{issue2.summary}"
            ],
            x: 4,
            y: 2
          }
        ],
        label: 'foo',
        type: 'bar'
      })
    end

    it 'appends issue_hint to each issue line when set' do
      board.cycletime = default_cycletime_config
      chart.issue_hints = { issue1 => '(hint for issue1)' }
      result = chart.data_set_for histogram_data: { 4 => [issue1] }, label: 'foo', color: 'red'
      expect(result[:data].first[:title][1]).to eq "#{issue1.key} : #{issue1.summary} (hint for issue1)"
    end
  end

  describe '#sort_items' do
    it 'sorts by key_as_i' do
      expect(chart.sort_items([issue10, issue1, issue2])).to eq([issue1, issue2, issue10])
    end
  end

  describe '#label_for_item' do
    it 'formats issue key and summary without hint' do
      expect(chart.label_for_item(issue1, hint: nil)).to eq("#{issue1.key} : #{issue1.summary}")
    end

    it 'appends hint when provided' do
      expect(chart.label_for_item(issue1, hint: '(my hint)')).to eq("#{issue1.key} : #{issue1.summary} (my hint)")
    end
  end
end
