# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cycletime_scatterplot'

describe CycletimeScatterplot do
  let(:chart) do
    CycletimeScatterplot.new.tap do |chart|
      chart.time_range = to_time('2020-01-01')..to_time('2020-02-01')
    end
  end

  context 'data_for_issue' do
    it '' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.data_for_issue issue).to eq({
        title: ['SP-10 : Check in people at an event (81 days)'],
        x: chart_format(issue.last_resolution),
        y: 81
      })
    end
  end

  context 'label_days' do
    it 'should return singular for 1' do
      expect(chart.label_days 1).to eq '1 day'
    end

    it 'should return singular for 0' do
      expect(chart.label_days 0).to eq '0 days'
    end
  end

  it 'should create_datasets' do
    board = load_complete_sample_board
    issue = load_issue('SP-10', board: board)

    board.cycletime = default_cycletime_config
    chart.issues = [issue]

    expect(chart.create_datasets [issue]).to eq([
      {
        backgroundColor: 'green',
        data: [
          {
            title: ['SP-10 : Check in people at an event (81 days)'],
            x: chart_format(issue.last_resolution),
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
        borderColor: 'green',
        borderDash: [6, 3],
        pointStyle: 'dash',
        hidden: true
      }
     ])
  end

  context 'group_issues' do
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue 'SP-1', board: board }

    it 'should render when no rules specified' do
      expected_rules = GroupingRules.new
      expected_rules.color = 'green'
      expected_rules.label = issue1.type
      expect(chart.group_issues([issue1])).to eq({
        expected_rules => [issue1]
      })
    end
  end
end
