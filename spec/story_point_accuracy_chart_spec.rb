# frozen_string_literal: true

require './spec/spec_helper'

describe StoryPointAccuracyChart do
  let(:subject) { StoryPointAccuracyChart.new }

  context 'story_points_at' do
    it 'handles no story points' do
      issue = empty_issue created: '2023-01-02'
      estimate = subject.story_points_at issue: issue, start_time: to_time('2023-01-03')
      expect(estimate).to be_nil
    end

    it 'handles a single estimate set' do
      issue = empty_issue created: '2023-01-02'
      issue.changes << mock_change(field: 'Story Points', value: '5.0', time: '2023-01-03')

      estimate = subject.story_points_at issue: issue, start_time: to_time('2023-01-04')
      expect(estimate).to be '5.0'
    end

    it 'handles estimates set before and after' do
      issue = empty_issue created: '2023-01-02'
      issue.changes << mock_change(field: 'Story Points', value: '5.0', time: '2023-01-03')
      issue.changes << mock_change(field: 'Story Points', value: '6.0', time: '2023-01-05')

      estimate = subject.story_points_at issue: issue, start_time: to_time('2023-01-04')
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
      it "should sort for [#{estimate1},#{count1}] and [#{estimate2},#{count2}]" do
        subject.y_axis sort_order: %w[XS S M L XL], label: 'points' if estimate1.is_a? String
        list = []
        list << [[estimate1, nil], [*1..count1]]
        list << [[estimate2, nil], [*1..count2]]

        actual = list.sort(&subject.hash_sorter).collect { |estimate, values| "#{estimate[0]}:#{values.size}" }
        expect(actual).to eq expected
      end
    end
  end

end
