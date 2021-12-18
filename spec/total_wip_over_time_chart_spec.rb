# frozen_string_literal: true

require './spec/spec_helper'

describe TotalWipOverTimeChart do
  let :chart do
    chart = TotalWipOverTimeChart.new
    chart.cycletime = defaultCycletimeConfig
    chart
  end

  context 'make_start_stop_sequence_for_issues' do
    it 'should handle no issues' do
      chart.issues = []
      expect(chart.make_start_stop_sequence_for_issues).to be_empty
    end

    it 'should handle one issue that is done' do
      issue = load_issue 'SP-10'
      chart.issues = [issue]
      expect(chart.make_start_stop_sequence_for_issues).to eq [
        [issue.created, 'start', issue],
        [issue.last_resolution, 'stop', issue]
      ]
    end

    it 'should handle one issue that isn\'t done' do
      issue = load_issue 'SP-1'
      chart.issues = [issue]
      expect(chart.make_start_stop_sequence_for_issues).to eq [
        [issue.created, 'start', issue]
      ]
    end

    it 'should handle one issue that is not even started' do
      block = lambda do |_|
        start_at last_resolution # Will be nil since the actual story hasn't finished.
        stop_at last_resolution
      end
      chart.cycletime = CycleTimeConfig.new parent_config: nil, label: nil, block: block
      chart.issues = [load_issue('SP-1')]
      expect(chart.make_start_stop_sequence_for_issues).to be_empty
    end

    it 'should sort items correctly' do
      issue1 = load_issue 'SP-1'
      issue2 = load_issue 'SP-10'

      chart.issues = [issue2, issue1]
      expect(chart.make_start_stop_sequence_for_issues).to eq [
        [issue1.created, 'start', issue1],
        [issue2.created, 'start', issue2],
        [issue2.last_resolution, 'stop', issue2]
      ]
    end
  end

  context 'make_chart_data' do
    it 'should handle empty list' do
      expect(chart.make_chart_data(issue_start_stops: [])).to be_empty
    end

    it 'should handle multiple items starting at once with nothing after' do
      issue1  = load_issue('SP-1')
      issue2  = load_issue('SP-2')

      issue_start_stops = [
        [DateTime.parse('2021-10-10'), 'start', issue1],
        [DateTime.parse('2021-10-10'), 'start', issue2]
      ]

      expect(chart.make_chart_data(issue_start_stops: issue_start_stops)).to eq [
        [DateTime.parse('2021-10-10'), [issue1, issue2], []]
      ]
    end

    it 'should handle multiple items' do
      issue1  = load_issue('SP-1')
      issue2  = load_issue('SP-2')
      issue10 = load_issue('SP-10')

      issue_start_stops = [
        [DateTime.parse('2021-10-10'), 'start', issue1],
        [DateTime.parse('2021-10-10'), 'start', issue2],

        [DateTime.parse('2021-10-12'), 'start', issue10],
        [DateTime.parse('2021-10-14'), 'stop', issue10]
      ]

      expect(chart.make_chart_data(issue_start_stops: issue_start_stops)).to eq [
        [DateTime.parse('2021-10-10'), [issue1, issue2], []],
        [DateTime.parse('2021-10-12'), [issue1, issue10, issue2], []],
        [DateTime.parse('2021-10-14'), [issue1, issue10, issue2], [issue10]]
      ]
    end

    it 'should handle invalid actions' do
      issue1 = load_issue('SP-1')
      issue_start_stops = [
        [DateTime.parse('2021-10-10'), 'foo', issue1]
      ]

      expect { chart.make_chart_data(issue_start_stops: issue_start_stops) }.to raise_error 'Unexpected action foo'
    end
  end

  context 'chart_data_starting_entry' do
    let(:issue1)  { load_issue 'SP-1' }
    let(:issue2)  { load_issue 'SP-2' }
    let(:issue10) { load_issue 'SP-10' }

    it 'should fabricate an empty line when no chart data' do
      chart_data = []
      date = Date.parse('2021-10-10')

      expect(chart.chart_data_starting_entry chart_data: chart_data, date: date).to eq [
        date, [], []
      ]
    end

    it 'return exact data when we have it' do
      date = Date.parse('2021-10-10')
      chart_data = [
        [date - 1, [issue1],  [issue2]],
        [date,     [issue2],  [issue10]],
        [date + 1, [issue10], [issue1]]
      ]

      expect(chart.chart_data_starting_entry chart_data: chart_data, date: date).to eq [
        date, [issue2], [issue10]
      ]
    end

    it 'return an earlier value if no match on the exact date' do
      date = Date.parse('2021-10-10')
      chart_data = [
        [date - 1, [issue1],  [issue2]],
        [date + 1, [issue2],  [issue10]],
        [date + 2, [issue10], [issue1]]
      ]

      expect(chart.chart_data_starting_entry chart_data: chart_data, date: date).to eq [
        date, [issue1], [issue2]
      ]
    end

  end
end
