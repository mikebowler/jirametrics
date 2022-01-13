# frozen_string_literal: true

require './spec/spec_helper'
require './lib/throughput_chart'

describe ThroughputChart do
  context 'calculate_time_periods' do
    # October 11 is a Monday

    it 'should return empty list if no complete periods' do
      chart = ThroughputChart.new
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-13')
      expect(chart.calculate_time_periods).to be_empty
    end

    it 'works for a single period starting on a Monday' do
      chart = ThroughputChart.new
      chart.date_range = Date.parse('2021-10-11')..Date.parse('2021-10-18')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for a single period starting on a Sunday' do
      chart = ThroughputChart.new
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-17')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for a single period not starting on a Monday or Sunday' do
      chart = ThroughputChart.new
      chart.date_range = Date.parse('2021-10-05')..Date.parse('2021-10-19')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for multiple periods starting on a Monday' do
      chart = ThroughputChart.new
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-26')
      expect(chart.calculate_time_periods).to eq [
        Date.parse('2021-10-11')..Date.parse('2021-10-17'),
        Date.parse('2021-10-18')..Date.parse('2021-10-24')
      ]
    end
  end

  context 'throughput_dataset' do
    it 'should work' do
      issue1 = load_issue('SP-1')
      issue1.changes.clear
      issue1.changes << mock_change(field: 'resolution', value: 'done', time: '2021-10-12T01:00:00')

      issue2 = load_issue('SP-2')
      issue2.changes.clear
      issue2.changes << mock_change(field: 'resolution', value: 'done', time: '2021-10-13T01:00:00')

      issue10 = load_issue('SP-10') # This one should be ignored
      issue10.changes.clear

      subject = ThroughputChart.new
      subject.issues = [issue1, issue2, issue10]
      subject.cycletime = defaultCycletimeConfig

      puts subject.cycletime.stopped_time(issue1)
      puts subject.cycletime.stopped_time(issue2)
      dataset = subject.throughput_dataset periods: [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
      expect(dataset).to eq [
        {
          title: ['2 items completed', 'SP-1 : Create new draft event', 'SP-2 : Update existing event'],
          x: Date.parse('2021-10-17'),
          y: 2
        }
      ]
    end
  end
end
