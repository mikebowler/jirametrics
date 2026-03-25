# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/throughput_chart'

describe ThroughputChart do
  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:issue2) { load_issue 'SP-2', board: board }
  let(:issue10) { load_issue 'SP-10', board: board }

  context 'calculate_time_periods' do
    # October 11 is a Monday

    it 'returns empty list if no complete periods' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-13')
      expect(chart.calculate_time_periods).to be_empty
    end

    it 'works for a single period starting on a Monday' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2021-10-11')..Date.parse('2021-10-18')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for a single period starting on a Sunday' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-17')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for a single period not starting on a Monday or Sunday' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2021-10-05')..Date.parse('2021-10-19')
      expect(chart.calculate_time_periods).to eq [Date.parse('2021-10-11')..Date.parse('2021-10-17')]
    end

    it 'works for multiple periods starting on a Monday' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2021-10-10')..Date.parse('2021-10-26')
      expect(chart.calculate_time_periods).to eq [
        Date.parse('2021-10-11')..Date.parse('2021-10-17'),
        Date.parse('2021-10-18')..Date.parse('2021-10-24')
      ]
    end
  end

  context 'throughput_dataset' do
    it 'returns correct data' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'resolution', value: 'done', time: '2021-10-12T01:00:00')

      issue2.changes.clear
      add_mock_change(issue: issue2, field: 'resolution', value: 'done', time: '2021-10-13T01:00:00')

      issue10.changes.clear

      subject = described_class.new empty_config_block
      subject.issues = [issue1, issue2, issue10]
      board.cycletime = default_cycletime_config

      dataset = subject.throughput_dataset(
        periods: [Date.parse('2021-10-11')..Date.parse('2021-10-17')],
        completed_issues: [issue1, issue2]
      )
      expect(dataset).to eq [
        {
          title: [
            '2 items closed between 2021-10-11 and 2021-10-17',
            'SP-1 : Create new draft event',
            'SP-2 : Update existing event'
          ],
          x: '2021-10-17T23:59:59',
          y: 2
        }
      ]
    end

    it 'includes label_hint in title when set' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'resolution', value: 'done', time: '2021-10-12T01:00:00')

      subject = described_class.new empty_config_block
      subject.issues = [issue1]
      board.cycletime = default_cycletime_config

      dataset = subject.throughput_dataset(
        periods: [Date.parse('2021-10-11')..Date.parse('2021-10-17')],
        completed_issues: [issue1],
        label_hint: 'Done'
      )
      expect(dataset.first[:title].first).to eq '1 items closed with Done between 2021-10-11 and 2021-10-17'
    end

    it 'appends issue_hint to each issue line when set' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'resolution', value: 'done', time: '2021-10-12T01:00:00')

      subject = described_class.new empty_config_block
      subject.issues = [issue1]
      board.cycletime = default_cycletime_config
      subject.instance_variable_set(:@issue_hints, { issue1 => '(priority: high)' })

      dataset = subject.throughput_dataset(
        periods: [Date.parse('2021-10-11')..Date.parse('2021-10-17')],
        completed_issues: [issue1]
      )
      expect(dataset.first[:title][1]).to eq 'SP-1 : Create new draft event (priority: high)'
    end

    context 'custom mode via @issue_periods' do
      it 'groups issues by last_day_of_period instead of stop date range' do
        issue1.changes.clear
        add_mock_change(issue: issue1, field: 'resolution', value: 'done', time: '2021-10-12T01:00:00')

        issue2.changes.clear
        add_mock_change(issue: issue2, field: 'resolution', value: 'done', time: '2021-11-05T01:00:00')

        subject = described_class.new empty_config_block
        subject.issues = [issue1, issue2]
        board.cycletime = default_cycletime_config
        jan31 = Date.parse('2026-01-31')
        feb28 = Date.parse('2026-02-28')
        subject.instance_variable_set(:@issue_periods, { issue1 => jan31, issue2 => feb28 })
        subject.instance_variable_set(:@issue_hints, {})

        dataset = subject.throughput_dataset(
          periods: [Date.parse('2026-01-01')..jan31, Date.parse('2026-02-01')..feb28],
          completed_issues: [issue1, issue2]
        )
        expect(dataset[0][:y]).to eq 1
        expect(dataset[0][:x]).to eq '2026-01-31T23:59:59'
        expect(dataset[1][:y]).to eq 1
        expect(dataset[1][:x]).to eq '2026-02-28T23:59:59'
      end
    end
  end

  context 'calculate_custom_periods' do
    it 'builds ranges from unique last_day_of_period values' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2026-01-01')..Date.parse('2026-03-31')
      jan31 = Date.parse('2026-01-31')
      feb28 = Date.parse('2026-02-28')
      chart.instance_variable_set(:@issue_periods, { issue1 => jan31, issue2 => feb28 })

      expect(chart.calculate_custom_periods).to eq [
        Date.parse('2026-01-01')..jan31,
        Date.parse('2026-02-01')..feb28
      ]
    end

    it 'deduplicates and sorts periods' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2026-01-01')..Date.parse('2026-03-31')
      jan31 = Date.parse('2026-01-31')
      chart.instance_variable_set(:@issue_periods, { issue1 => jan31, issue2 => jan31 })

      expect(chart.calculate_custom_periods).to eq [Date.parse('2026-01-01')..jan31]
    end
  end

  context 'run' do
    it 'sets x-axis min and max to the full date range' do
      chart = described_class.new(empty_config_block)
      chart.file_system = MockFileSystem.new
      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/throughput_chart.erb'),
        json: :not_mocked
      )
      chart.date_range = Date.parse('2021-10-11')..Date.parse('2021-11-07')
      chart.time_range = to_time('2021-10-11')..to_time('2021-11-07')
      chart.holiday_dates = []
      chart.issues = []
      chart.settings = {}

      output = chart.run
      expect(output).to include('min: "2021-10-11"')
      expect(output).to include('max: "2021-11-08"')
    end
  end

  context 'throughput_forecaster_url' do
    it 'builds URL with samples and not-started count' do
      chart = described_class.new empty_config_block
      chart.instance_variable_set(:@throughput_samples, [3, 5, 2])
      chart.instance_variable_set(:@not_started_count, 2)

      url = chart.throughput_forecaster_url
      expect(url).to start_with('https://focusedobjective.com/throughput?')
      expect(url).to include('throughputMode=data')
      expect(url).to include('samplesText=3%2C5%2C2')
      expect(url).to include('storyLow=2')
      expect(url).to include('storyHigh=2')
    end

    it 'uses zero for not-started count when all issues are started' do
      chart = described_class.new empty_config_block
      chart.instance_variable_set(:@throughput_samples, [1])
      chart.instance_variable_set(:@not_started_count, 0)

      url = chart.throughput_forecaster_url
      expect(url).to include('storyLow=0')
      expect(url).to include('storyHigh=0')
    end
  end

  context 'weekly_throughput_dataset' do
    it 'includes label_hint when provided' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2021-10-11')..Date.parse('2021-10-17')
      result = chart.weekly_throughput_dataset(
        completed_issues: [], label: 'Story', color: 'blue', label_hint: 'These are stories'
      )
      expect(result[:label_hint]).to eq 'These are stories'
    end

    it 'includes label_hint as nil when not provided' do
      chart = described_class.new empty_config_block
      chart.date_range = Date.parse('2021-10-11')..Date.parse('2021-10-17')
      result = chart.weekly_throughput_dataset(completed_issues: [], label: 'Story', color: 'blue')
      expect(result[:label_hint]).to be_nil
    end
  end

  context 'group_issues' do
    it 'renders when no rules specified' do
      expected_rules = GroupingRules.new
      expected_rules.color = '--type-story-color'
      expected_rules.label = 'Story'
      expect(described_class.new(empty_config_block).group_issues([issue1])).to eq({
        expected_rules => [issue1]
      })
    end

    it 'renders when grouping_rules are used' do
      subject = described_class.new empty_config_block
      subject.grouping_rules do |issue, rules|
        if issue.key == 'SP-1'
          rules.color = 'orange'
          rules.label = 'foo'
        else
          rules.ignore
        end
      end
      expected_rules = GroupingRules.new
      expected_rules.color = 'orange'
      expected_rules.label = 'foo'
      expect(subject.group_issues([issue1, issue2])).to eq({
        expected_rules => [issue1]
      })
    end
  end
end
