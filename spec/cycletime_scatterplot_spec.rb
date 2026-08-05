# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cycletime_scatterplot'

describe CycletimeScatterplot do
  let(:chart) do
    described_class.new(empty_config_block).tap do |chart|
      chart.time_range = to_time('2020-01-01')..to_time('2020-02-01')
    end
  end

  describe '#cycletime_unit' do
    it 'accepts :days (the only supported unit)' do
      expect { chart.cycletime_unit :days }.not_to raise_error
    end

    it 'raises NotImplementedError for any other unit' do
      expect { chart.cycletime_unit :hours }.to raise_error(
        NotImplementedError, /CycletimeScatterplot only supports :days/
      )
    end
  end

  describe '#data_for_issue' do
    it 'gets data' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.data_for_issue issue).to eq({
        title: ['SP-10 : Check in people at an event (81 days)'],
        x: chart_format(issue.last_resolution.time),
        y: 81
      })
    end

    it 'appends issue_hint when set' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      chart.issue_hints = { issue => '(priority: high)' }
      expect(chart.data_for_issue(issue)[:title])
        .to eq ['SP-10 : Check in people at an event (81 days) (priority: high)']
    end
  end

  describe '#label_days' do
    it 'returns singular for 1' do
      expect(chart.label_days 1).to eq '1 day'
    end

    it 'returns singular for 0' do
      expect(chart.label_days 0).to eq '0 days'
    end
  end

  it 'creates datasets' do
    board = load_complete_sample_board
    issue = load_issue('SP-10', board: board)

    board.cycletime = default_cycletime_config
    chart.issues = [issue]

    expect(chart.create_datasets [issue]).to eq([
      {
        backgroundColor: CssVariable['--type-story-color'],
        data: [
          {
            title: ['SP-10 : Check in people at an event (81 days)'],
            x: chart_format(issue.last_resolution.time),
            y: 81
         }
        ],
        fill: false,
        label: 'Story (85% at 81 days)',
        showLine: false
      },
      {
        type: 'line',
        label: 'Story Trendline',
        data: [],
        fill: false,
        borderWidth: 1,
        markerType: 'none',
        borderColor: CssVariable['--type-story-color'],
        borderDash: [6, 3],
        pointStyle: 'dash',
        hidden: true
      }
     ])
  end

  describe '#group_issues' do
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue 'SP-1', board: board }

    it 'renders when no rules specified' do
      expected_rules = GroupingRules.new
      expected_rules.color = '--type-story-color'
      expected_rules.label = issue1.type
      expect(chart.group_issues([issue1])).to eq({
        expected_rules => [issue1]
      })
    end
  end

  describe '#x_value' do
    it 'returns the stop time from cycletime' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.x_value(issue)).to eq issue.last_resolution.time
    end
  end

  describe '#y_value' do
    it 'returns the cycletime in days' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.y_value(issue)).to eq 81
    end
  end

  describe '#title_value' do
    it 'formats key, summary, and cycletime' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.title_value(issue)).to eq 'SP-10 : Check in people at an event (81 days)'
    end

    it 'appends hint when set' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      chart.issue_hints = { issue => '(priority: high)' }
      expect(chart.title_value(issue)).to eq 'SP-10 : Check in people at an event (81 days) (priority: high)'
    end
  end

  describe '#cap_y_axis' do
    it 'is disabled by default' do
      expect(chart.y_axis_cap_percentile).to be_nil
    end

    it 'defaults to the 98th percentile when enabled with no argument' do
      chart.cap_y_axis
      expect(chart.y_axis_cap_percentile).to eq 98
    end

    it 'accepts an explicit percentile' do
      chart.cap_y_axis percentile: 90
      expect(chart.y_axis_cap_percentile).to eq 90
    end
  end

  describe '#percentile_value' do
    it 'returns the value at the requested percentile, min-filtered' do
      items = Array.new(20) { |index| "item#{index}" }
      values = (1..19).to_a + [500] # 20 values; index 20*85/100 = 17 -> sorted[17] = 18
      allow(chart).to receive(:y_value) { |item| values[items.index(item)] }
      expect(chart.percentile_value(items, 85)).to eq 18
    end
  end

  describe '#compute_cap' do
    let(:items) { Array.new(20) { |index| "item#{index}" } }
    let(:values) { (1..19).to_a + [500] }

    before { allow(chart).to receive(:y_value) { |item| values[items.index(item)] } }

    it 'returns nil when capping is disabled' do
      expect(chart.compute_cap(items)).to be_nil
    end

    it 'returns nil when nothing exceeds the cutoff' do
      chart.cap_y_axis percentile: 100
      expect(chart.compute_cap(items)).to be_nil
    end

    it 'computes the cap layout from the full set' do
      chart.cap_y_axis percentile: 85 # cutoff = 18; values 19 and 500 exceed it
      cap = chart.compute_cap(items)
      aggregate_failures do
        expect(cap[:cutoff]).to eq 18
        expect(cap[:outlier_count]).to eq 2
        expect(cap[:sep]).to be_within(0.001).of(18 + (18 * 0.06))
        expect(cap[:axis_max]).to eq (18 + (18 * 0.06) + (18 * 0.15)).ceil
        expect(cap[:pin_row]).to be_within(0.001).of((18 + (18 * 0.06)) + (18 * 0.15 * 0.55))
      end
    end
  end

  describe 'capping in create_datasets' do
    let(:board) { load_complete_sample_board }
    let(:issue) { load_issue('SP-10', board: board) }

    before { board.cycletime = default_cycletime_config }

    it 'leaves points unchanged when capping is disabled' do
      point = chart.create_datasets([issue]).first[:data].first
      aggregate_failures do
        expect(point[:y]).to eq 81
        expect(point).not_to have_key(:over)
      end
    end

    it 'remaps an over-cap point to the pinned row and flags it' do
      # SP-10 (81 days) and SP-14 (78 days). Percentile 1 on this pair makes 78 the cutoff,
      # so SP-10's 81 lands strictly above it and gets remapped.
      other_issue = load_issue('SP-14', board: board)
      the_items = [issue, other_issue]
      chart.cap_y_axis percentile: 1
      scatter = chart.create_datasets(the_items).first
      sp10_title = ['SP-10 : Check in people at an event (81 days)']
      point = scatter[:data].find { |data_point| data_point[:title] == sp10_title }
      cap = chart.compute_cap(the_items)
      aggregate_failures do
        expect(point[:over]).to be true
        expect(point[:y]).to eq cap[:pin_row]
        expect(point[:title]).to eq ['SP-10 : Check in people at an event (81 days)']
      end
    end
  end

  describe 'statistics are unaffected by capping' do
    let(:board) { load_complete_sample_board }
    let(:issues) { %w[SP-10 SP-14].map { |key| load_issue(key, board: board) } }

    before { board.cycletime = default_cycletime_config }

    it 'computes the same 85% line with capping on and off' do
      uncapped = chart.calculate_percent_line(issues)
      chart.cap_y_axis percentile: 90
      capped = chart.calculate_percent_line(issues)
      expect(capped).to eq uncapped
    end
  end
end
