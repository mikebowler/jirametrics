# frozen_string_literal: true

require './spec/spec_helper'
require './spec/mock_estimation_configuration'

describe EstimateAccuracyChart do
  let(:board) { sample_board }
  let(:chart) do
    described_class.new(empty_config_block).tap do |chart|
      chart.all_boards = { board.id => board }
    end
  end

  context 'estimate_at' do
    it 'handles no story points' do
      issue = empty_issue created: '2023-01-02'
      estimate = chart.estimate_at issue: issue, start_time: to_time('2023-01-03')
      expect(estimate).to be_nil
    end

    it 'handles a single estimate set' do
      issue = empty_issue created: '2023-01-02'
      add_mock_change(issue: issue, field: 'Story Points', value: '5.0', time: '2023-01-03')

      estimate = chart.estimate_at issue: issue, start_time: to_time('2023-01-04')
      expect(estimate).to be '5.0'
    end

    it 'handles estimates set before and after' do
      issue = empty_issue created: '2023-01-02'
      add_mock_change(issue: issue, field: 'Story Points', value: '5.0', time: '2023-01-03')
      add_mock_change(issue: issue, field: 'Story Points', value: '6.0', time: '2023-01-05')

      estimate = chart.estimate_at issue: issue, start_time: to_time('2023-01-04')
      expect(estimate).to be '5.0'
    end

    it 'handles estimates in time' do
      issue = empty_issue created: '2023-01-02'
      two_days = (60 * 60 * 24 * 2).to_s
      add_mock_change(issue: issue, field: 'timeoriginalestimate', value: two_days, time: '2023-01-03')

      estimate = chart.estimate_at(
        issue: issue,
        start_time: to_time('2023-01-04'),
        estimation_configuration: MockEstimationConfiguration.new(units: :seconds, field_id: 'timeoriginalestimate')
      )
      expect(estimate).to eq 2.0
    end
  end

  context 'estimate_label' do
    it 'renders story points' do
      expect(chart.estimate_label estimate: '2.0', estimation_units: :story_points).to eq '2.0pts'
    end

    it 'renders time' do
      expect(chart.estimate_label estimate: '2.0', estimation_units: :seconds).to eq '2.0 days'
    end

    it 'renders a category response' do
      chart.y_axis label: 'foo', sort_order: %w[one two]
      expect(chart.estimate_label estimate: '2.0', estimation_units: :story_points).to eq '2.0'
    end

    it 'renders a default response' do
      expect(chart.estimate_label estimate: '2.0', estimation_units: :unknown).to eq '2.0'
    end
  end

  context 'hash_sorter' do
    [ # lowest to highest
      [5, 2, 5, 2, ['5:2', '5:2']],
      [5, 2, 5, 3, ['5:2', '5:3']],
      ['XL', 2, 'S', 2, ['S:2', 'XL:2']],
      ['M', 2, 'L', 2, ['M:2', 'L:2']],
      ['A', 2, 'L', 2, ['L:2', 'A:2']]

    ].each do |estimate1, count1, estimate2, count2, expected|
      it "sorts for [#{estimate1},#{count1}] and [#{estimate2},#{count2}]" do
        chart.y_axis sort_order: %w[XS S M L XL], label: 'points' if estimate1.is_a? String
        list = []
        list << [[estimate1, nil], [*1..count1]]
        list << [[estimate2, nil], [*1..count2]]

        actual = list.sort(&chart.hash_sorter).collect { |estimate, values| "#{estimate[0]}:#{values.size}" }
        expect(actual).to eq expected
      end
    end
  end

  context 'correlation_coefficient' do
    it 'returns nil for an empty hash' do
      expect(chart.correlation_coefficient({})).to be_nil
    end

    it 'returns nil when there is only one data point' do
      expect(chart.correlation_coefficient({ [1, 2] => [:a] })).to be_nil
    end

    it 'returns nil when one list has zero variance' do
      hash = { [5, 1] => [:a], [5, 2] => [:b], [5, 3] => [:c] }
      expect(chart.correlation_coefficient(hash)).to be_nil
    end

    it 'returns 1.0 for a perfect positive correlation' do
      hash = { [1, 1] => [:a], [2, 2] => [:b], [3, 3] => [:c] }
      expect(chart.correlation_coefficient(hash)).to eq 1.0
    end

    it 'returns -1.0 for a perfect negative correlation' do
      hash = { [1, 3] => %i[a], [2, 2] => %i[b], [3, 1] => %i[c] }
      expect(chart.correlation_coefficient(hash)).to eq(-1.0)
    end

    it 'counts multiple issues at the same key as individual data points' do
      # [1,2] has 2 issues so it contributes 2 data points, changing the result
      # vs treating each key as a single point (which would give r=0.5)
      hash = { [1, 2] => %i[a b], [3, 1] => %i[c], [5, 3] => %i[d] }
      expect(chart.correlation_coefficient(hash)).to be_within(0.0001).of(2.0 / Math.sqrt(22))
    end
  end

  context 'split_into_completed_and_aging' do
    it 'works for no issues' do
      expect(chart.split_into_completed_and_aging issues: []).to eq [{}, {}]
    end

    it 'works for one of each' do
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-05')
      board = sample_board
      chart.all_boards = { board.id => board }
      issue1 = load_issue 'SP-1', board: board
      add_mock_change(issue: issue1, field: 'Story Points', value: 5, time: '2024-01-01')

      issue2 = load_issue 'SP-2', board: board
      add_mock_change(issue: issue2, field: 'Story Points', value: 5, time: '2024-01-01')

      issue_with_no_estimate = load_issue 'SP-1', board: board
      issue_not_started = load_issue 'SP-1', board: board

      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-02', '2024-01-02T01:00:00'],
        [issue2, '2024-01-02', nil],
        [issue_with_no_estimate, '2024-01-02', nil]
      ]

      issues = [issue1, issue2, issue_not_started, issue_with_no_estimate]
      expect(chart.split_into_completed_and_aging issues: issues).to eq [
        { [5.0, 1] => [issue1] },
        { [5.0, 4] => [issue2] }
      ]
    end
  end
end
