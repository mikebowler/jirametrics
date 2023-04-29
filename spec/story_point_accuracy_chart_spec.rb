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
end
