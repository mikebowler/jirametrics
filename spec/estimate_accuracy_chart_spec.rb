# frozen_string_literal: true

require './spec/spec_helper'

describe EstimateAccuracyChart do
  let(:chart) { described_class.new empty_config_block }

  context 'story_points_at' do
    it 'handles no story points' do
      issue = empty_issue created: '2023-01-02'
      estimate = chart.story_points_at issue: issue, start_time: to_time('2023-01-03')
      expect(estimate).to be_nil
    end

    it 'handles a single estimate set' do
      issue = empty_issue created: '2023-01-02'
      issue.changes << mock_change(field: 'Story Points', value: '5.0', time: '2023-01-03')

      estimate = chart.story_points_at issue: issue, start_time: to_time('2023-01-04')
      expect(estimate).to be '5.0'
    end

    it 'handles estimates set before and after' do
      issue = empty_issue created: '2023-01-02'
      issue.changes << mock_change(field: 'Story Points', value: '5.0', time: '2023-01-03')
      issue.changes << mock_change(field: 'Story Points', value: '6.0', time: '2023-01-05')

      estimate = chart.story_points_at issue: issue, start_time: to_time('2023-01-04')
      expect(estimate).to be '5.0'
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

  context 'split_into_completed_and_aging' do
    it 'works for no issues' do
      expect(chart.split_into_completed_and_aging issues: []).to eq [{}, {}]
    end

    it 'works for one of each' do
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-05')
      board = sample_board
      issue1 = load_issue 'SP-1', board: board
      issue1.changes << mock_change(field: 'Story Points', value: 5, time: '2024-01-01')

      issue2 = load_issue 'SP-2', board: board
      issue2.changes << mock_change(field: 'Story Points', value: 5, time: '2024-01-01')

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
