# frozen_string_literal: true

require './spec/spec_helper'

describe ExpeditedChart do
  let(:chart) do
    chart = ExpeditedChart.new('expedite')
    chart.date_range = Date.parse('2022-01-01')..Date.parse('2022-01-30')
    chart
  end
  let(:issue1) { load_issue('SP-1').tap { |issue| issue.changes.clear } }

  context 'prepare_expedite_data' do
    it 'should handle issue with no changes' do
      expect(chart.prepare_expedite_data(issue1)).to be_empty
    end

    it 'should handle issue with no expedite' do
      issue1.changes << mock_change(field: 'status', value: 'start', time: '2022-01-01')
      expect(chart.prepare_expedite_data(issue1)).to be_empty
    end

    it 'should ignore ending expedite before one ever set' do
      # Why test for this case? Because we've seen it in production.
      issue1.changes << mock_change(field: 'priority', value: '', time: '2022-01-01')
      expect(chart.prepare_expedite_data(issue1)).to be_empty
    end

    it 'should handle expedite starting and not ending' do
      issue1.changes << mock_change(field: 'priority', value: 'expedite', time: '2022-01-01')
      expect(chart.prepare_expedite_data(issue1)).to eq [
        [DateTime.parse('2022-01-01'), :expedite_start]
      ]
    end

    it 'should ignore an expedite that started and stopped outside the date range' do
      issue1.changes << mock_change(field: 'priority', value: 'expedite', time: '2020-01-01')
      issue1.changes << mock_change(field: 'priority', value: '', time: '2020-01-02')
      expect(chart.prepare_expedite_data(issue1)).to be_empty
    end

    it 'should include an expedite that started before the date range and ended after' do
      issue1.changes << mock_change(field: 'priority', value: 'expedite', time: '2020-01-01')
      issue1.changes << mock_change(field: 'priority', value: '', time: '2023-01-02')
      expect(chart.prepare_expedite_data(issue1)).to eq [
        [DateTime.parse('2020-01-01'), :expedite_start],
        [DateTime.parse('2023-01-02'), :expedite_stop]
      ]
    end
  end

  context 'later_date' do
    it 'should handle null first parameter' do
      date2 = Date.today
      expect(chart.later_date(nil, date2)).to be date2
    end

    it 'should handle nil second parameter' do
      date1 = Date.today
      expect(chart.later_date(date1, nil)).to be date1
    end

    it 'should handle nil for both parameters' do
      expect(chart.later_date(nil, nil)).to be_nil
    end

    it 'should handle happy path' do
      date2 = Date.today
      date1 = date2 + 1
      expect(chart.later_date(date1, date2)).to be date1
    end

  end
end
