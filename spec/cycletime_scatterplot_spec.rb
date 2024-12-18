# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cycletime_scatterplot'

describe CycletimeScatterplot do
  let(:chart) do
    described_class.new(empty_config_block).tap do |chart|
      chart.time_range = to_time('2020-01-01')..to_time('2020-02-01')
    end
  end

  context 'data_for_issue' do
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
  end

  context 'label_days' do
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

  context 'group_issues' do
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
end
