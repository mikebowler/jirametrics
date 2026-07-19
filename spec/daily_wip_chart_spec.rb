# frozen_string_literal: true

require './spec/spec_helper'

def flatten_issue_groups issue_rules_by_active_dates
  result = []
  issue_rules_by_active_dates.keys.sort.each do |date|
    issue_rules_by_active_dates[date].each do |issue, rules|
      result << [date.to_s, issue.key, rules.label, rules.color, rules.group_priority]
    end
  end
  result
end

describe DailyWipChart do
  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:issue2) { load_issue 'SP-2', board: board }
  let(:issue3) { empty_issue created: '2022-01-01', board: board, key: 'SP-9' }

  let(:chart) do
    chart = described_class.new empty_config_block
    chart.date_range = Date.parse('2022-01-01')..Date.parse('2022-04-02')
    chart
  end

  describe '#configure_rule' do
    it 'uses RawJavascript for color pairs' do
      chart.issues = [issue1]
      chart.grouping_rules do |_issue, rules|
        rules.label = 'Group A'
        rules.color = ['#4bc14b', '#2a7a2a']
      end
      rules = chart.configure_rule issue: issue1, date: Date.parse('2022-01-15')
      expect(rules.color).to be_a RawJavascript
    end
  end

  describe '#run' do
    it 'sets x-axis min and max to the full date range' do
      chart = described_class.new(empty_config_block)
      chart.file_system = MockFileSystem.new
      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/daily_wip_chart.erb'),
        json: :not_mocked
      )
      chart.date_range = Date.parse('2021-10-11')..Date.parse('2021-11-07')
      chart.time_range = to_time('2021-10-11')..to_time('2021-11-07')
      chart.holiday_dates = []
      chart.issues = []
      chart.settings = {}

      output = chart.run
      aggregate_failures do
        expect(output).to include('min: "2021-10-11"')
        expect(output).to include('max: "2021-11-08"')
      end
    end
  end

  describe '#group_issues_by_active_dates' do
    it 'returns nothing when no issues' do
      chart.issues = []
      expect(chart.group_issues_by_active_dates).to be_empty
    end

    it 'returns raise exception when no grouping rules set' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      chart.issues = [issue1]
      expect { chart.group_issues_by_active_dates }.to raise_error(
        'If you use this class directly then you must provide grouping_rules'
      )
    end

    it 'returns nothing when grouping rules ignore everything' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      chart.issues = [issue1]
      chart.grouping_rules do |_issue, rules|
        rules.ignore
      end
      expect(chart.group_issues_by_active_dates).to be_empty
    end

    it 'makes a single group for one issue' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      chart.issues = [issue1]
      chart.grouping_rules do |_issue, rules|
        rules.label = 'foo'
        rules.color = 'blue'
      end

      expect(flatten_issue_groups chart.group_issues_by_active_dates).to eq([
        ['2022-02-02', 'SP-1', 'foo', 'blue', 0]
      ])
    end

    it 'skips an issue that neither started nor stopped' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil]
      ]
      chart.issues = [issue1]
      chart.grouping_rules do |_issue, rules|
        rules.label = 'foo'
        rules.color = 'blue'
      end

      expect(flatten_issue_groups chart.group_issues_by_active_dates).to be_empty
    end

    it 'includes an issue that stopped but never started' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, to_time('2022-01-03T14:00:00')]
      ]
      chart.issues = [issue1]
      chart.grouping_rules do |_issue, rules|
        rules.label = 'foo'
        rules.color = 'blue'
      end

      expect(flatten_issue_groups chart.group_issues_by_active_dates).to eq([
        ['2022-01-01', 'SP-1', 'foo', 'blue', 0],
        ['2022-01-02', 'SP-1', 'foo', 'blue', 0],
        ['2022-01-03', 'SP-1', 'foo', 'blue', 0]
      ])
    end

    it 'runs an issue that started but never stopped through to the end of the range' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-04-01T11:00:00'), nil] # started near the end, never stopped
      ]
      chart.issues = [issue1]
      chart.grouping_rules do |_issue, rules|
        rules.label = 'foo'
        rules.color = 'blue'
      end

      expect(flatten_issue_groups chart.group_issues_by_active_dates).to eq([
        ['2022-04-01', 'SP-1', 'foo', 'blue', 0],
        ['2022-04-02', 'SP-1', 'foo', 'blue', 0] # date_range.end
      ])
    end

    it 'keeps processing later issues after skipping one that never started or stopped' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil], # skipped
        [issue2, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      chart.issues = [issue1, issue2]
      chart.grouping_rules do |_issue, rules|
        rules.label = 'foo'
        rules.color = 'blue'
      end

      expect(flatten_issue_groups chart.group_issues_by_active_dates).to eq([
        ['2022-02-02', 'SP-2', 'foo', 'blue', 0]
      ])
    end

    it 'passes the issue to the grouping rules' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      chart.issues = [issue1]
      chart.grouping_rules do |issue, rules|
        rules.label = issue.key
        rules.color = 'blue'
      end

      expect(flatten_issue_groups chart.group_issues_by_active_dates).to eq([
        ['2022-02-02', 'SP-1', 'SP-1', 'blue', 0]
      ])
    end

    it 'passes each active date to the grouping rules as current_date' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-03T14:00:00')]
      ]
      chart.issues = [issue1]
      chart.grouping_rules do |_issue, rules|
        rules.label = rules.current_date.to_s
        rules.color = 'blue'
      end

      expect(flatten_issue_groups chart.group_issues_by_active_dates).to eq([
        ['2022-02-02', 'SP-1', '2022-02-02', 'blue', 0],
        ['2022-02-03', 'SP-1', '2022-02-03', 'blue', 0]
      ])
    end
  end

  describe '#select_possible_rules' do
    it 'returns empty for no data' do
      expect(chart.select_possible_rules issue_rules_by_active_date: {}).to be_empty
    end

    it 'returns one group' do
      rules = DailyGroupingRules.new
      rules.label = 'foo'
      rules.color = 'red'
      rules.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rules]
        ]
      }
      expect(chart.select_possible_rules(issue_rules_by_active_date).collect(&:group)).to eq([
        ['foo', 'red', false]
      ])
    end

    it 'returns two different groups' do
      rule1 = DailyGroupingRules.new
      rule1.label = 'foo'
      rule1.color = 'red'
      rule1.group_priority = 0

      rule2 = DailyGroupingRules.new
      rule2.label = 'bar'
      rule2.color = 'gray'
      rule2.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule1],
          [issue2, rule2]
        ]
      }
      expect(chart.select_possible_rules(issue_rules_by_active_date).collect(&:group)).to eq([
        ['foo', 'red', false],
        ['bar', 'gray', false]
      ])
    end

    it 'returns one group when the same one is used twice' do
      rule1 = DailyGroupingRules.new
      rule1.label = 'foo'
      rule1.color = 'red'
      rule1.group_priority = 0

      rule2 = DailyGroupingRules.new
      rule2.label = 'foo'
      rule2.color = 'red'
      rule2.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule1],
          [issue2, rule2]
        ]
      }
      expect(chart.select_possible_rules(issue_rules_by_active_date).collect(&:group)).to eq([
        ['foo', 'red', false]
      ])
    end

    it 'returns two groups when label is the same but highlight differs' do
      rule1 = DailyGroupingRules.new
      rule1.label = 'foo'
      rule1.color = 'red'
      rule1.group_priority = 0

      rule2 = DailyGroupingRules.new
      rule2.label = 'foo'
      rule2.color = 'red'
      rule2.highlight = true
      rule2.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule1],
          [issue2, rule2]
        ]
      }
      expect(chart.select_possible_rules(issue_rules_by_active_date).collect(&:group)).to eq([
        ['foo', 'red', false],
        ['foo', 'red', true]
      ])
    end
  end

  describe '#make_data_set' do
    it 'positive' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = 'red'
      rule.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule],
          [issue2, rule]
        ]
      }

      data_set = chart.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      expect(data_set).to eq({
        backgroundColor: 'red',
        borderColor: CssVariable['--wip-chart-border-color'],
        borderRadius: 0,
        borderWidth: 0,
        data: [
          {
            title: ['foo (2 issues)', 'SP-1 : Create new draft event ', 'SP-2 : Update existing event '],
            x: to_date('2022-01-01'),
            y: 2
          }
        ],
        label: 'foo',
        label_hint: nil,
        type: 'bar'
      })
    end

    it 'negative' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = '--body-background'
      rule.group_priority = -1

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [
          [issue1, rule],
          [issue2, rule]
        ]
      }

      data_set = chart.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      expect(data_set).to eq({
        backgroundColor: CssVariable['--body-background'],
        borderColor: CssVariable['--wip-chart-border-color'],
        borderRadius: 5,
        borderWidth: 1,
        data: [
          {
            title: ['foo (2 issues)', 'SP-1 : Create new draft event ', 'SP-2 : Update existing event '],
            x: to_date('2022-01-01'),
            y: -2
          }
        ],
        label: 'foo',
        label_hint: nil,
        type: 'bar'
      })
    end

    it 'uses diagonal pattern when highlight is true' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = 'red'
      rule.highlight = true
      rule.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [[issue1, rule]]
      }

      data_set = chart.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      expect(data_set[:backgroundColor]).to eq RawJavascript.new('createDiagonalPattern("red")')
    end

    it 'includes label_hint from the grouping rule' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = 'red'
      rule.label_hint = 'foo Full description of the group'

      issue_rules_by_active_date = { to_date('2022-01-01') => [[issue1, rule]] }

      data_set = chart.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      aggregate_failures do
        expect(data_set[:label_hint]).to eq 'foo Full description of the group'
        expect(data_set[:data].first[:title].first).to eq 'foo Full description of the group (1 issue)'
      end
    end

    it 'appends * to label when label_suffix is provided' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = 'red'
      rule.highlight = true
      rule.group_priority = 0

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [[issue1, rule]]
      }

      data_set = chart.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date,
                                     label_suffix: '*'
      aggregate_failures do
        expect(data_set[:label]).to eq 'foo*'
        expect(data_set[:data].first[:title].first).to eq 'foo* (1 issue)'
      end
    end

    it 'treats a strictly positive group_priority as a positive bar' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = 'red'
      rule.group_priority = 5

      issue_rules_by_active_date = { to_date('2022-01-01') => [[issue1, rule]] }

      data_set = chart.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      aggregate_failures do
        expect(data_set[:data].first[:y]).to eq 1
        expect(data_set[:borderRadius]).to eq 0
      end
    end

    it 'includes only the issues in the rule group, sorted by issue key' do
      rule_a = DailyGroupingRules.new.tap { |r| r.label = 'a'; r.color = 'red'; r.group_priority = 0 }
      rule_b = DailyGroupingRules.new.tap { |r| r.label = 'b'; r.color = 'blue'; r.group_priority = 0 }

      issue_rules_by_active_date = {
        to_date('2022-01-01') => [[issue2, rule_a], [issue1, rule_a], [issue3, rule_b]]
      }

      data_set = chart.make_data_set grouping_rule: rule_a, issue_rules_by_active_date: issue_rules_by_active_date
      titles = data_set[:data].first[:title]
      aggregate_failures do
        expect(titles.first).to eq 'a (2 issues)' # issue3 (rule_b) excluded
        expect(titles[1]).to start_with 'SP-1'     # sorted ahead of SP-2 despite input order
        expect(titles[2]).to start_with 'SP-2'
      end
    end

    it 'strips the summary and appends the issue_hint in each title' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = 'red'
      rule.group_priority = 0
      rule.issue_hint = '(hint)'
      allow(issue1).to receive(:summary).and_return('  padded summary  ')

      issue_rules_by_active_date = { to_date('2022-01-01') => [[issue1, rule]] }

      data_set = chart.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      expect(data_set[:data].first[:title]).to eq ['foo (1 issue)', 'SP-1 : padded summary (hint)']
    end

    it 'falls back to a random color when the grouping rule has none' do
      rule = DailyGroupingRules.new
      rule.label = 'foo'
      rule.color = nil
      rule.group_priority = 0
      allow(chart).to receive(:random_color).and_return('#abcdef')

      issue_rules_by_active_date = { to_date('2022-01-01') => [[issue1, rule]] }

      data_set = chart.make_data_set grouping_rule: rule, issue_rules_by_active_date: issue_rules_by_active_date
      expect(data_set[:backgroundColor]).to eq '#abcdef'
    end
  end

  describe '#trend_line_data_set' do
    let(:sample_data) do
      [
        {
          label: 'cat',
          data: [
            { x: to_date('2024-01-01'), y: 3 },
            { x: to_date('2024-01-02'), y: 4 },
            { x: to_date('2024-01-03'), y: 5 }
          ]
        }
      ]
    end

    it 'returns nil if no data' do
      expect(chart.trend_line_data_set data: {}, group_labels: ['one'], color: 'red').to be_nil
    end

    it 'returns nil if no group labels match' do
      expect(chart.trend_line_data_set data: sample_data, group_labels: ['one'], color: 'red').to be_nil
    end

    it 'processes trend line' do
      expect(chart.trend_line_data_set data: sample_data, group_labels: ['cat'], color: 'red').to eq(
        borderColor: 'red',
        borderDash: [6, 3],
        borderWidth: 1,
        data: [
          { x: '2023-12-29', y: 0 },
          { x: '2023-12-29', y: 0 }
        ],
        fill: false,
        hidden: false,
        label: 'Trendline',
        markerType: 'none',
        pointStyle: 'dash',
        type: 'line'
      )
    end

    it 'clamps the trend line to the maximum daily wip' do
      # A rising trend extrapolated to the end of the range is capped at the highest daily wip (200).
      data = [{ label: 'cat', data: [
        { x: to_date('2022-01-02'), y: 1 },
        { x: to_date('2022-02-01'), y: 50 },
        { x: to_date('2022-03-01'), y: 200 }
      ] }]
      result = chart.trend_line_data_set data: data, group_labels: ['cat'], color: 'red'
      expect(result[:data].last[:y]).to eq 200
    end
  end

  describe '#daily_wip_totals' do
    it 'sums the daily wip across every dataset whose label is in group_labels' do
      data = [
        { label: 'a', data: [{ x: to_date('2024-01-01'), y: 3 }, { x: to_date('2024-01-02'), y: 4 }] },
        { label: 'b', data: [{ x: to_date('2024-01-01'), y: 10 }] }, # same date as 'a' -> summed
        { label: 'c', data: [{ x: to_date('2024-01-01'), y: 99 }] }  # not in group_labels -> excluded
      ]
      expect(chart.daily_wip_totals(data, %w[a b])).to eq(
        to_date('2024-01-01') => 13, # 3 + 10
        to_date('2024-01-02') => 4
      )
    end

    it 'keeps processing later datasets after skipping one not in group_labels' do
      data = [
        { label: 'skip', data: [{ x: to_date('2024-01-01'), y: 99 }] },
        { label: 'keep', data: [{ x: to_date('2024-01-01'), y: 5 }] }
      ]
      expect(chart.daily_wip_totals(data, ['keep'])).to eq(to_date('2024-01-01') => 5)
    end
  end
end
