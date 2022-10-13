# frozen_string_literal: true

require './spec/spec_helper'

describe ExpeditedChart do
  let(:chart) do
    chart = ExpeditedChart.new('expedite')
    chart.date_range = Date.parse('2022-01-01')..Date.parse('2022-01-30')
    chart
  end
  let(:issue1) { load_issue('SP-1').tap { |issue| issue.changes.clear } }
  let(:issue2) { load_issue('SP-2').tap { |issue| issue.changes.clear } }

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
        [Time.parse('2022-01-01'), :expedite_start]
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
        [Time.parse('2020-01-01'), :expedite_start],
        [Time.parse('2023-01-02'), :expedite_stop]
      ]
    end
  end

  context 'find_expedited_issues' do
    it 'should handle no issues' do
      chart.issues = []
      expect(chart.find_expedited_issues).to be_empty
    end

    it 'should handle no issues with expedite' do
      chart.issues = [issue1, issue2]
      expect(chart.find_expedited_issues).to be_empty
    end

    it 'should handle one issue with expedite' do
      issue1.changes << mock_change(field: 'priority', value: 'expedite', time: '2020-01-01')
      chart.issues = [issue1, issue2]
      expect(chart.find_expedited_issues).to eq [issue1]
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

  context 'make_expedite_lines_data_set' do
    xit 'should handle the case with no start or stop times or data' do
      config = CycleTimeConfig.new parent_config: nil, label: nil, block: nil
      config.start_at ->(_issue) {}
      config.stop_at  ->(_issue) {}
      chart.cycletime = config

      expect(chart.make_expedite_lines_data_set(issue: issue1, expedite_data: [])).to be_nil
    end

    xit 'should handle one of everything' do
      base_date = Date.parse('2022-01-01')
      chart.cycletime = mock_cycletime_config stub_values: [[issue1, base_date, base_date + 3]]

      expedite_data = [
        [base_date + 1, :expedite_start],
        [base_date + 2, :expedite_stop]
      ]

      expect(chart.make_expedite_lines_data_set(issue: issue1, expedite_data: expedite_data)).to eq({
        type: 'line',
        label: issue1.key,
        data: [
          { expedited: 0, title: ['SP-1 Started : Create new draft event'],       x: '2022-01-01', y: 198 },
          { expedited: 1, title: ['SP-1 Expedited : Create new draft event'],     x: '2022-01-02', y: 199 },
          { expedited: 0, title: ['SP-1 Not expedited : Create new draft event'], x: '2022-01-03', y: 200 },
          { expedited: 0, title: ['SP-1 Completed : Create new draft event'],     x: '2022-01-04', y: 201 }
        ],
        fill: false,
        showLine: true,
        backgroundColor: %w[orange red gray green],
        pointBorderColor: 'black',
        pointStyle: %w[rect circle circle rect],
        segment: ExpeditedChart::EXPEDITED_SEGMENT
      })
    end

    xit 'should handle an expedite that starts but doesnt end' do
      base_date = Date.parse('2022-01-01')
      chart.cycletime = mock_cycletime_config stub_values: [[issue1, base_date, nil]]

      expedite_data = [
        [base_date + 1, :expedite_start]
      ]

      expect(chart.make_expedite_lines_data_set(issue: issue1, expedite_data: expedite_data)).to eq({
        type: 'line',
        label: issue1.key,
        data: [
          { expedited: 0, title: ['SP-1 Started : Create new draft event'],       x: '2022-01-01', y: 198 },
          { expedited: 1, title: ['SP-1 Expedited : Create new draft event'],     x: '2022-01-02', y: 199 },
          { expedited: 1, title: ['SP-1 Still ongoing : Create new draft event'], x: '2022-01-30', y: 227 }
        ],
        fill: false,
        showLine: true,
        backgroundColor: %w[orange red blue],
        pointBorderColor: 'black',
        pointStyle: %w[rect circle dash],
        segment: ExpeditedChart::EXPEDITED_SEGMENT
      })
    end

    xit 'should raise an exception for unexpected expedite data' do
      chart.cycletime = mock_cycletime_config stub_values: [[issue1, nil, nil]]

      expedite_data = [
        [Date.today, :invalid_state]
      ]

      expect { chart.make_expedite_lines_data_set(issue: issue1, expedite_data: expedite_data) }.to(
        raise_error('Unexpected action: invalid_state')
      )
    end
  end
end
