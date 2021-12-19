# frozen_string_literal: true

require './spec/spec_helper'

describe TotalWipOverTimeChart do
  let(:issue1)  { load_issue 'SP-1' }
  let(:issue2)  { load_issue 'SP-2' }
  let(:issue10) { load_issue 'SP-10' }

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
      chart.issues = [issue10]
      expect(chart.make_start_stop_sequence_for_issues).to eq [
        [issue10.created, 'start', issue10],
        [issue10.last_resolution, 'stop', issue10]
      ]
    end

    it 'should handle one issue that isn\'t done' do
      chart.issues = [issue1]
      expect(chart.make_start_stop_sequence_for_issues).to eq [
        [issue1.created, 'start', issue1]
      ]
    end

    it 'should handle one issue that is not even started' do
      block = lambda do |_|
        start_at last_resolution # Will be nil since the actual story hasn't finished.
        stop_at last_resolution
      end
      chart.cycletime = CycleTimeConfig.new parent_config: nil, label: nil, block: block
      chart.issues = [issue1]
      expect(chart.make_start_stop_sequence_for_issues).to be_empty
    end

    it 'should sort items correctly' do
      chart.issues = [issue10, issue1]
      expect(chart.make_start_stop_sequence_for_issues).to eq [
        [issue1.created, 'start', issue1],
        [issue10.created, 'start', issue10],
        [issue10.last_resolution, 'stop', issue10]
      ]
    end
  end

  context 'make_chart_data' do
    it 'should handle empty list' do
      expect(chart.make_chart_data(issue_start_stops: [])).to be_empty
    end

    it 'should handle multiple items starting at once with nothing after' do
      issue_start_stops = [
        [DateTime.parse('2021-10-10'), 'start', issue1],
        [DateTime.parse('2021-10-10'), 'start', issue2]
      ]

      expect(chart.make_chart_data(issue_start_stops: issue_start_stops)).to eq [
        [DateTime.parse('2021-10-10'), [issue1, issue2], []]
      ]
    end

    it 'should handle multiple items' do
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
      issue_start_stops = [
        [DateTime.parse('2021-10-10'), 'foo', issue1]
      ]

      expect { chart.make_chart_data(issue_start_stops: issue_start_stops) }.to raise_error 'Unexpected action foo'
    end
  end

  context 'chart_data_starting_entry' do
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

  context 'incomplete_dataset' do
    let(:october10) { Date.parse('2021-10-10') }
    let(:october11) { Date.parse('2021-10-11') }

    it 'should handle empty chart data' do
      chart_data = []
      age_range = nil..500
      date_range = october10..october11
      dataset = chart.incomplete_dataset(
        chart_data: chart_data, age_range: age_range, date_range: date_range, label: 'foo'
      )

      expect(dataset).to eq [
        {
          title: ['foo'],
          x: october10,
          y: 0
        },
        {
          title: ['foo'],
          x: october11,
          y: 0
        }
      ]
    end

    it 'should handle one item of chart data' do
      chart_data = [[october10, [issue1], [issue2]]]
      age_range = nil..500
      date_range = october10..october11
      dataset = chart.incomplete_dataset(
        chart_data: chart_data, age_range: age_range, date_range: date_range, label: 'foo'
      )

      expect(dataset).to eq [
        {
          title: ['foo', 'SP-1 : Create new draft event (115 days)'],
          x: october10,
          y: 1
        },
       {
          title: ['foo', 'SP-1 : Create new draft event (116 days)'],
          x: october11,
          y: 1
        }
      ]
    end

    it 'should exclude anything outside the age range' do
      chart_data = [[october10, [issue1], [issue2]]]
      age_range = nil..2
      date_range = october10..october11
      dataset = chart.incomplete_dataset(
        chart_data: chart_data, age_range: age_range, date_range: date_range, label: 'foo'
      )

      expect(dataset).to eq [
        {
          title: ['foo'],
          x: october10,
          y: 0
        },
       {
          title: ['foo'],
          x: october11,
          y: 0
        }
      ]
    end
  end

  context 'completed_dataset' do
    let(:october10) { Date.parse('2021-10-10') }
    let(:october11) { Date.parse('2021-10-11') }
    let(:october12) { Date.parse('2021-10-12') }

    it 'should handle nothing completed' do
      chart.date_range = october10..october11

      chart_data = [
        [october10, [issue1], []], # Nothing completed that day
        [october12, [issue1], [issue2]] # Out of range
      ]
      dataset = chart.completed_dataset(
        chart_data: chart_data
      )

      expect(dataset).to eq({
        backgroundColor: '#009900',
        borderRadius: '5',
        data: [],
        label: 'Completed that day',
        type: 'bar'
      })
    end

    it 'should handle one item completed' do
      chart.date_range = october10..october11

      chart_data = [[october10, [issue1], [issue2]]]
      dataset = chart.completed_dataset(
        chart_data: chart_data
      )

      expect(dataset).to eq({
        backgroundColor: '#009900',
        borderRadius: '5',
        data: [
          {
            title: ['Work items completed', 'SP-2 : Update existing event'],
            x: october10,
            y: -1
          }

        ],
        label: 'Completed that day',
        type: 'bar'
      })
    end
  end
end
