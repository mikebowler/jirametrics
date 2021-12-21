# frozen_string_literal: true

require './spec/spec_helper'

describe DailyChartItemGenerator do
  let(:date_range) { Date.parse('2021-06-17')..Date.parse('2021-06-19') }
  # let(:date_range) { Date.parse('2021-10-10')..Date.parse('2021-10-13') }
  let(:issue1)  { load_issue 'SP-1' }
  let(:issue2)  { load_issue 'SP-2' }
  let(:issue10) { load_issue 'SP-10' }

  context 'make_start_stop_sequence_for_issues' do
    it 'should handle no issues' do
      subject = DailyChartItemGenerator.new issues: [], cycletime: defaultCycletimeConfig, date_range: date_range
      expect(subject.make_start_stop_sequence_for_issues).to be_empty
    end

    it 'should handle one issue that is done' do
      subject = DailyChartItemGenerator.new issues: [issue10], cycletime: defaultCycletimeConfig, date_range: date_range
      expect(subject.make_start_stop_sequence_for_issues).to eq [
        [issue10.created, 'start', issue10],
        [issue10.last_resolution, 'stop', issue10]
      ]
    end

    it 'should handle one issue that isn\'t done' do
      subject = DailyChartItemGenerator.new issues: [issue1], cycletime: defaultCycletimeConfig, date_range: date_range
      expect(subject.make_start_stop_sequence_for_issues).to eq [
        [issue1.created, 'start', issue1]
      ]
    end

    it 'should handle one issue that is not even started' do
      block = lambda do |_|
        start_at last_resolution # Will be nil since the actual story hasn't finished.
        stop_at last_resolution
      end
      cycletime = CycleTimeConfig.new parent_config: nil, label: nil, block: block
      subject = DailyChartItemGenerator.new issues: [issue1], cycletime: cycletime, date_range: date_range
      expect(subject.make_start_stop_sequence_for_issues).to be_empty
    end

    it 'should sort items correctly' do
      issues = [issue10, issue1]
      subject = DailyChartItemGenerator.new issues: issues, cycletime: defaultCycletimeConfig, date_range: date_range
      expect(subject.make_start_stop_sequence_for_issues).to eq [
        [issue1.created, 'start', issue1],
        [issue10.created, 'start', issue10],
        [issue10.last_resolution, 'stop', issue10]
      ]
    end
  end

  context 'populate_days' do
    it 'should handle empty list' do
      subject = DailyChartItemGenerator.new issues: nil, cycletime: defaultCycletimeConfig, date_range: date_range
      subject.populate_days(start_stop_sequence: [])

      expect(subject.to_test).to eq [
        ['2021-06-17', nil, nil],
        ['2021-06-18', nil, nil],
        ['2021-06-19', nil, nil]
      ]
    end

    it 'should handle multiple items starting at once with nothing after' do
      subject = DailyChartItemGenerator.new issues: nil, cycletime: defaultCycletimeConfig, date_range: date_range
      issue_start_stops = [
        [DateTime.parse('2021-06-17'), 'start', issue1],
        [DateTime.parse('2021-06-17'), 'start', issue2]
      ]
      subject.populate_days(start_stop_sequence: issue_start_stops)

      expect(subject.to_test).to eq [
        ['2021-06-17', [issue1, issue2], []],
        ['2021-06-18', nil, nil],
        ['2021-06-19', nil, nil]
      ]
    end

    it 'should handle multiple items' do
      subject = DailyChartItemGenerator.new issues: nil, cycletime: defaultCycletimeConfig, date_range: date_range
      issue_start_stops = [
        [DateTime.parse('2021-06-17'), 'start', issue1],
        [DateTime.parse('2021-06-17'), 'start', issue2],

        [DateTime.parse('2021-06-19'), 'start', issue10],
        [DateTime.parse('2021-06-19'), 'stop', issue10]
      ]
      subject.populate_days(start_stop_sequence: issue_start_stops)

      expect(subject.to_test).to eq [
        ['2021-06-17', [issue1, issue2], []],
        ['2021-06-18', nil, nil],
        ['2021-06-19', [issue1, issue2, issue10], [issue10]]
      ]
    end

    it 'should handle invalid actions' do
      subject = DailyChartItemGenerator.new issues: nil, cycletime: defaultCycletimeConfig, date_range: date_range
      issue_start_stops = [
        [DateTime.parse('2021-10-10'), 'foo', issue1]
      ]

      expect { subject.populate_days(start_stop_sequence: issue_start_stops) }.to raise_error 'Unexpected action: foo'
    end
  end

end
