# frozen_string_literal: true

require './spec/spec_helper'

describe Sprint do
  let(:subject) { SprintBurndown.new }
  let(:sprint) do
    Sprint.new(raw: {
      'id' => 1,
      'self' => 'https://improvingflow.atlassian.net/rest/agile/1.0/sprint/1',
      'state' => 'active',
      'name' => 'Scrum Sprint 1',
      'startDate' => '2022-03-26T00:00:00z',
      'endDate' => '2022-04-09T00:00:00z',
      'originBoardId' => 2,
      'goal' => 'Do something'
    })
  end

  context 'guess_sprint_end_time' do
    it 'should return completed when provided' do
      sprint_data = []
      sprint.raw['completedDate'] = '2022-04-10T00:00:00z'
      expect(subject.guess_sprint_end_time(sprint, sprint_data)).to eq Time.parse('2022-04-10T00:00:00z')
    end

    it 'should return end when there has been no activity in the sprint' do
      sprint_data = []
      expect(subject.guess_sprint_end_time(sprint, sprint_data)).to eq Time.parse('2022-04-09T00:00:00z')
    end

    it 'should return end when end is older than any activity' do
      sprint_data = [
        SprintIssueChangeData.new(
          time: Time.parse('2022-04-09T00:00:00z'), action: :foo, value: nil, issue: nil, story_points: nil
        )
      ]
      expect(subject.guess_sprint_end_time(sprint, sprint_data)).to eq Time.parse('2022-04-09T00:00:00z')
    end

    it 'should return oldest activity time when thats older than end' do
      sprint_data = [
        SprintIssueChangeData.new(
          time: Time.parse('2022-10-09T00:00:00z'), action: :foo, value: nil, issue: nil, story_points: nil
        )
      ]
      expect(subject.guess_sprint_end_time(sprint, sprint_data)).to eq Time.parse('2022-10-09T00:00:00z')
    end
  end

  context 'single_issue_change_data' do
    let(:issue) { load_issue('SP-1').tap { |issue| issue.changes.clear } }

    it 'should return empty list for no changes' do
      subject.cycletime = mock_cycletime_config stub_values: []
      expect(subject.single_issue_change_data(issue, sprint.name)).to be_empty
    end

    it 'should return start and end only' do
      subject.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-02-01']
      ]
      issue.changes << mock_change(field: 'Sprint', value: sprint.name, time: '2022-01-03')
      issue.changes << mock_change(field: 'Sprint', value: '', old_value: sprint.name, time: '2022-01-04')
      expect(subject.single_issue_change_data(issue, sprint)).to eql [
        SprintIssueChangeData.new(
          action: :enter_sprint, time: Time.parse('2022-01-03'), value: nil, issue: issue, story_points: nil
        ),
        SprintIssueChangeData.new(
          action: :leave_sprint, time: Time.parse('2022-01-04'), value: nil, issue: issue, story_points: nil
        )
      ]
    end

    it 'should change points at various times for item that was in sprint from the beginning' do
      subject.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-01-05']
      ]
      issue.changes << mock_change(field: 'Sprint', value: sprint.name, time: '2022-01-01')
      issue.changes << mock_change(field: 'Story Points', value: 2.0, old_value: nil, time: '2022-01-02')
      sprint.raw['startDate'] = '2021-01-03'
      issue.changes << mock_change(field: 'Story Points', value: 4.0, old_value: 2.0, time: '2022-01-04')
      # Issue closes on Jan 5
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2022-01-05')
      issue.changes << mock_change(field: 'Story Points', value: '6.0', time: '2022-01-06')

      expect(subject.single_issue_change_data(issue, sprint)).to eql [
        SprintIssueChangeData.new(
          action: :enter_sprint, time: Time.parse('2022-01-01'), value: nil, issue: issue, story_points: nil
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: Time.parse('2022-01-02'), value: 2.0, issue: issue, story_points: 2.0
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: Time.parse('2022-01-04'), value: 2.0, issue: issue, story_points: 4.0
        ),
        SprintIssueChangeData.new(
          action: :issue_stopped, time: Time.parse('2022-01-05'), value: nil, issue: issue, story_points: 0.0
        )
      ]
    end
  end
end
