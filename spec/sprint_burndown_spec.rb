# frozen_string_literal: true

require './spec/spec_helper'

describe Sprint do
  let(:subject) do
    SprintBurndown.new.tap do |chart|
      # Larger than the sprint
      chart.time_range = to_time('2022-03-01')..to_time('2022-04-11T23:59:59 +00:00')
      chart.date_range = chart.time_range.begin.to_date..chart.time_range.end.to_date
    end
  end

  let(:sprint) do
    Sprint.new(raw: {
      'id' => 1,
      'self' => 'https://improvingflow.atlassian.net/rest/agile/1.0/sprint/1',
      'state' => 'active',
      'name' => 'Scrum Sprint 1',
      'activatedDate' => '2022-03-26T00:00:00z',
      'endDate' => '2022-04-09T00:00:00z',
      'originBoardId' => 2,
      'goal' => 'Do something'
    }, timezone_offset: '+00:00')
  end

  context 'options' do
    it 'should handle points_only' do
      subject.options = :points_only
      expect([subject.use_story_points, subject.use_story_counts]).to eq([true, false])
    end

    it 'should handle counts_only' do
      subject.options = :counts_only
      expect([subject.use_story_points, subject.use_story_counts]).to eq([false, true])
    end

    it 'should handle points_and_counts' do
      subject.options = :points_and_counts
      expect([subject.use_story_points, subject.use_story_counts]).to eq([true, true])
    end

    it 'should handle neither' do
      expect { subject.options = :foo }.to raise_error 'Unexpected option: foo'
    end
  end

  context 'changes_for_one_issue' do
    let(:board) { load_complete_sample_board }
    let(:issue) { load_issue('SP-1', board: board).tap { |issue| issue.changes.clear } }

    it 'should return empty list for no changes' do
      board.cycletime = mock_cycletime_config stub_values: []
      expect(subject.changes_for_one_issue(issue: issue, sprint: sprint)).to be_empty
    end

    it 'should return start and end only' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-02-01']
      ]
      issue.changes << mock_change(field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-03')
      issue.changes << mock_change(field: 'Sprint', value: '', value_id: '', time: '2022-01-04')
      expect(subject.changes_for_one_issue(issue: issue, sprint: sprint)).to eql [
        SprintIssueChangeData.new(
          action: :enter_sprint, time: to_time('2022-01-03'), value: 0.0, issue: issue, story_points: 0.0
        ),
        SprintIssueChangeData.new(
          action: :leave_sprint, time: to_time('2022-01-04'), value: 0.0, issue: issue, story_points: 0.0
        )
      ]
    end

    it 'should change points at various times for item that was in sprint from the beginning' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-01-05']
      ]
      issue.changes << mock_change(field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      issue.changes << mock_change(field: 'Story Points', value: 2.0, old_value: nil, time: '2022-01-02')
      sprint.raw['activatedDate'] = '2021-01-03'
      issue.changes << mock_change(field: 'Story Points', value: 4.0, old_value: 2.0, time: '2022-01-04')
      # Issue closes on Jan 5
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2022-01-05')
      issue.changes << mock_change(field: 'Story Points', value: '6.0', time: '2022-01-06')

      expect(subject.changes_for_one_issue(issue: issue, sprint: sprint)).to eql [
        SprintIssueChangeData.new(
          action: :enter_sprint, time: to_time('2022-01-01'), value: 0.0, issue: issue, story_points: 0.0
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: to_time('2022-01-02'), value: 2.0, issue: issue, story_points: 2.0
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: to_time('2022-01-04'), value: 2.0, issue: issue, story_points: 4.0
        ),
        SprintIssueChangeData.new(
          action: :issue_stopped, time: to_time('2022-01-05'), value: -4.0, issue: issue, story_points: 4.0
        )
      ]
    end
  end

  context 'data_set_by_story_points' do
    let(:issue1) { load_issue('SP-1').tap { |issue| issue.changes.clear } }
    let(:issue2) { load_issue('SP-2').tap { |issue| issue.changes.clear } }

    it 'should handle an empty active sprint' do
      change_data = []
      expect(subject.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 0.0, title: 'Sprint started with 0.0 points' },
        { x: '2022-04-11T23:59:59+0000', y: 0.0, title: 'Sprint still active. 0.0 points still in progress.' }
      ]
    end

    it 'should handle an empty completed sprint' do
      change_data = []
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      expect(subject.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 0.0, title: 'Sprint started with 0.0 points' },
        { x: '2022-04-10T00:00:00+0000', y: 0.0, title: 'Sprint ended with 0.0 points unfinished' }
      ]
    end

    it 'should handle complex case with active sprint' do
      change_data = [
        # Sprint start is 2022-03-26

        SprintIssueChangeData.new( # Has points assigned but not in sprint at start
          time: to_time('2022-03-23'), action: :story_points, value: 2.0, issue: issue2, story_points: 2.0
        ),

        SprintIssueChangeData.new(
          time: to_time('2022-03-23'), action: :story_points, value: 5.0, issue: issue1, story_points: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :story_points, value: 7.0, issue: issue1, story_points: 12.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 5.0, issue: issue1, story_points: 12.0
        ),

        # sprint starts here

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :story_points, value: 5.0, issue: issue1, story_points: 5.0
        ),
        SprintIssueChangeData.new( # Should be ignored because it's in sprint yet
          time: to_time('2022-03-27'), action: :story_points, value: 2.0, issue: issue2, story_points: 4.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :enter_sprint, value: nil, issue: issue2, story_points: 4.0
        )
      ]
      expect(subject.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 12.0, title: 'Sprint started with 12.0 points' },
        { x: '2022-03-27T00:00:00+0000', y: 17.0, title: 'SP-1 Story points changed from 0.0 points to 5.0 points' },
        { x: '2022-03-28T00:00:00+0000', y: 21.0, title: 'SP-2 Added to sprint with 4.0 points' },
        { x: '2022-04-11T23:59:59+0000', y: 21.0, title: 'Sprint still active. 21.0 points still in progress.' }
      ]
    end

    it 'should ignore changes after sprint end' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-23'), action: :story_points, value: 5.0, issue: issue1, story_points: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 5.0, issue: issue1, story_points: 5.0
        ),

        # sprint starts and then ends here

        SprintIssueChangeData.new(
          time: to_time('2022-04-11'), action: :story_points, value: -2.0, issue: issue1, story_points: 3.0
        )
      ]
      expect(subject.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 5.0, title: 'Sprint started with 5.0 points' },
        { x: '2022-04-10T00:00:00+0000', y: 5.0, title: 'Sprint ended with 5.0 points unfinished' }
      ]
    end

    it 'should handle an issue being removed mid-sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, story_points: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, story_points: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :leave_sprint, value: -5.0, issue: issue1, story_points: 5.0
        )
      ]
      expect(subject.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 12.0, title: 'Sprint started with 12.0 points' },
        { x: '2022-03-27T00:00:00+0000', y: 7.0, title: 'SP-1 Removed from sprint with 5.0 points' },
        { x: '2022-04-10T00:00:00+0000', y: 7.0, title: 'Sprint ended with 7.0 points unfinished' }
      ]
    end

    it 'should handle an issue being completed mid-sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, story_points: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, story_points: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :issue_stopped, value: -5.0, issue: issue1, story_points: 5.0
        )
      ]
      expect(subject.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 12.0, title: 'Sprint started with 12.0 points' },
        { x: '2022-03-27T00:00:00+0000', y: 7.0, title: 'SP-1 Completed with 5.0 points' },
        { x: '2022-04-10T00:00:00+0000', y: 7.0, title: 'Sprint ended with 7.0 points unfinished' }
      ]
    end

    it 'should handle an issue with zero points being completed mid-sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 0.0, issue: issue1, story_points: 0.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, story_points: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :issue_stopped, value: 0.0, issue: issue1, story_points: 0.0
        )
      ]
      expect(subject.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 7.0, title: 'Sprint started with 7.0 points' },
        { x: '2022-03-27T00:00:00+0000', y: 7.0, title: 'SP-1 Completed with 0.0 points' },
        { x: '2022-04-10T00:00:00+0000', y: 7.0, title: 'Sprint ended with 7.0 points unfinished' }
      ]
    end

    it 'should raise error if an illegal action is passed in' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :illegal_action, value: 0.0, issue: issue1, story_points: 0.0
        )
      ]
      expect { subject.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint) }.to(
        raise_error 'Unexpected action: illegal_action'
      )
    end
  end

  context 'data_set_by_story_counts' do
    let(:issue1) { load_issue('SP-1').tap { |issue| issue.changes.clear } }
    let(:issue2) { load_issue('SP-2').tap { |issue| issue.changes.clear } }

    it 'should handle an empty active sprint' do
      change_data = []
      expect(subject.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 0, title: 'Sprint started with 0 stories' },
        { x: '2022-04-11T23:59:59+0000', y: 0, title: 'Sprint still active. 0 issues in progress.' }
      ]
    end

    it 'should handle an empty completed sprint' do
      change_data = []
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      expect(subject.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 0, title: 'Sprint started with 0 stories' },
        { x: '2022-04-10T00:00:00+0000', y: 0, title: 'Sprint ended with 0 stories unfinished' }
      ]
    end

    it 'should handle complex case with active sprint' do
      change_data = [
        # Sprint start is 2022-03-26

        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 5.0, issue: issue1, story_points: 12.0
        ),

        # sprint starts here

        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :enter_sprint, value: nil, issue: issue2, story_points: 4.0
        )
      ]
      expect(subject.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 1.0, title: 'Sprint started with 1 stories' },
        { x: '2022-03-28T00:00:00+0000', y: 2.0, title: 'SP-2 Added to sprint' },
        { x: '2022-04-11T23:59:59+0000', y: 2.0, title: 'Sprint still active. 2 issues in progress.' }
      ]
    end

    it 'should handle an issue being removed mid-sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: nil, issue: issue1, story_points: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: nil, issue: issue2, story_points: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :leave_sprint, value: nil, issue: issue1, story_points: 5.0
        )
      ]
      expect(subject.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 2, title: 'Sprint started with 2 stories' },
        { x: '2022-03-27T00:00:00+0000', y: 1, title: 'SP-1 Removed from sprint' },
        { x: '2022-04-10T00:00:00+0000', y: 1, title: 'Sprint ended with 1 stories unfinished' }
      ]
    end

    it 'should handle an issue being completed mid-sprint and should ignore one after sprint end' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, story_points: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, story_points: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new( # This should be ignored
          time: to_time('2022-03-27'), action: :story_points, value: 4.0, issue: issue1, story_points: 9.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :issue_stopped, value: -5.0, issue: issue1, story_points: 5.0
        ),

        # sprint ends

        SprintIssueChangeData.new(
          time: to_time('2022-04-11'), action: :issue_stopped, value: -7.0, issue: issue1, story_points: 7.0
        )

      ]
      expect(subject.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
        { x: '2022-03-26T00:00:00+0000', y: 2, title: 'Sprint started with 2 stories' },
        { x: '2022-03-28T00:00:00+0000', y: 1, title: 'SP-1 Completed' },
        { x: '2022-04-10T00:00:00+0000', y: 1, title: 'Sprint ended with 1 stories unfinished' }
      ]
    end
  end
end
