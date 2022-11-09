# frozen_string_literal: true

require './spec/spec_helper'

def empty_issue created:
  Issue.new(
    raw: {
      'key' => 'SP-1',
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => to_time(created).to_s,
        'status' => {
          'name' => 'BrandNew!',
          'id' => '999'
        },
        'creator' => {
          'displayName' => 'Tolkien'
        }
      }
    },
    board: sample_board
  )
end

describe Issue do
  let(:board) do
    board = sample_board
    statuses = board.possible_statuses
    statuses.clear
    statuses << Status.new(name: 'Backlog', id: 1, category_name: 'ready', category_id: 2)
    statuses << Status.new(name: 'Selected for Development', id: 3, category_name: 'ready', category_id: 4)
    statuses << Status.new(name: 'In Progress', id: 5, category_name: 'in-flight', category_id: 6)
    statuses << Status.new(name: 'Review', id: 7, category_name: 'in-flight', category_id: 8)
    statuses << Status.new(name: 'Done', id: 9, category_name: 'finished', category_id: 10)
    board
  end

  it 'gets key' do
    issue = load_issue 'SP-2'
    expect(issue.key).to eql 'SP-2'
  end

  it 'gets url' do
    issue = load_issue 'SP-2'
    expect(issue.url).to eql 'https://improvingflow.atlassian.net/browse/SP-2'
  end

  it 'cannot fabricate url' do
    issue = load_issue 'SP-2'
    issue.raw['self'] = nil
    expect(issue.url).to be_nil
  end

  it 'gets created and updated' do
    raw = {
      'key' => 'SP-1',
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => '2021-08-29T18:00:00+00:00',
        'updated' => '2021-09-29T18:00:00+00:00',
        'status' => {
          'name' => 'BrandNew!',
          'id' => '999'
        },
        'creator' => {
          'displayName' => 'Tolkien'
        }
      }
    }
    issue = Issue.new raw: raw, board: sample_board
    expect([issue.created, issue.updated]).to eq [
      Time.parse('2021-08-29T18:00:00+00:00'),
      Time.parse('2021-09-29T18:00:00+00:00')
    ]
  end

  it 'gets simple history with a single status' do
    issue = load_issue 'SP-2'

    changes = [
      mock_change(field: 'status', value: 'Backlog', time: '2021-06-18T18:41:37.804+0000'),
      mock_change(field: 'priority', value: 'Medium', time: '2021-06-18T18:41:37.804+0000'),
      mock_change(field: 'status', value: 'Selected for Development', time: '2021-06-18T18:43:38+00:00')
    ]

    expect(issue.changes).to eq changes
  end

  it 'gets complex history with a mix of field types' do
    issue = load_issue 'SP-10'
    changes = [
      mock_change(field: 'status',     value: 'Backlog',                  time: '2021-06-18T18:42:52.754+0000'),
      mock_change(field: 'priority',   value: 'Medium',                   time: '2021-06-18T18:42:52.754+0000'),
      mock_change(field: 'status',     value: 'Selected for Development', time: '2021-08-29T18:06:28+00:00'),
      mock_change(field: 'Rank',       value: 'Ranked higher',            time: '2021-08-29T18:06:28+00:00'),
      mock_change(field: 'priority',   value: 'Highest',                  time: '2021-08-29T18:06:43+00:00'),
      mock_change(field: 'status',     value: 'In Progress',              time: '2021-08-29T18:06:55+00:00'),
      mock_change(field: 'status',     value: 'Selected for Development', time: '2021-09-06T04:33:11+00:00'),
      mock_change(field: 'Flagged',    value: 'Impediment',               time: '2021-09-06T04:33:30+00:00'),
      mock_change(field: 'priority',   value: 'Medium',                   time: '2021-09-06T04:33:50+00:00'),
      mock_change(field: 'Flagged',    value: '',                         time: '2021-09-06T04:33:55+00:00'),
      mock_change(field: 'status',     value: 'In Progress',              time: '2021-09-06T04:34:02+00:00'),
      mock_change(field: 'status',     value: 'Review',                   time: '2021-09-06T04:34:21+00:00'),
      mock_change(field: 'status',     value: 'Done',                     time: '2021-09-06T04:34:26+00:00'),
      mock_change(field: 'resolution', value: 'Done',                     time: '2021-09-06T04:34:26+00:00')
     ]
    expect(issue.changes).to eq changes
  end

  it "should default the first status if there really hasn't been any yet" do
    issue = empty_issue created: '2021-08-29T18:00:00+00:00'
    expect(issue.changes).to eq [
      mock_change(field: 'status', value: 'BrandNew!', time: '2021-08-29T18:00:00+00:00')
    ]
  end

  it 'first time in status' do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('In Progress').to_s).to eql '2021-08-29 18:06:55 +0000'
  end

  it "first time in status that doesn't match any" do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('NoStatus')).to be_nil
  end

  it 'first time not in status' do
    issue = load_issue 'SP-10'
    expect(issue.first_time_not_in_status('Backlog').to_s).to eql '2021-08-29 18:06:28 +0000'
  end

  it "first time not in status where it's never in that status" do
    raw = {
      'key' => 'SP-1',
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => '2021-08-29T18:00:00+00:00',
        'status' => {
          'name' => 'BrandNew!',
          'id' => '999'
        },
        'creator' => {
          'displayName' => 'Tolkien'
        }
      }
    }
    issue = Issue.new raw: raw, board: sample_board
    expect(issue.first_time_not_in_status('BrandNew!')).to be_nil
  end

  it "first time in status that doesn't match any" do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('NoStatus')).to be_nil
  end

  it "first time for any status change - created doesn't count as status change" do
    issue = load_issue 'SP-10'
    expect(issue.first_status_change_after_created.to_s).to eql '2021-08-29 18:06:28 +0000'
  end

  it 'first time in status category' do
    issue = load_issue 'SP-10', board: board
    issue.board.possible_statuses << Status.new(
      name: 'Done',
      id: 1,
      category_name: 'finished',
      category_id: 2
    )

    expect(issue.first_time_in_status_category('finished').to_s).to eq '2021-09-06 04:34:26 +0000'
  end

  it 'first status change after created' do
    issue = load_issue 'SP-10'
    expect(issue.first_status_change_after_created.to_s).to eql '2021-08-29 18:06:28 +0000'
  end

  it %(first status change after created, where there isn't anything after created) do
    raw = {
      'key' => 'SP-1',
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => '2021-08-29T18:00:00+00:00',
        'status' => {
          'name' => 'BrandNew!',
          'id' => '999'
        },
        'creator' => {
          'displayName' => 'Tolkien'
        }

      }
    }
    issue = Issue.new raw: raw, board: sample_board
    expect(issue.first_status_change_after_created).to be_nil
  end

  context 'currently_in_status' do
    it 'item moved to done and then back to in progress' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue.currently_in_status('Done')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue.currently_in_status('Done').to_s).to eql '2021-10-02 00:00:00 +0000'
    end
  end

  context 'still_in_status' do
    it 'item moved to done and then back to in progress' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue.still_in_status('Done')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue.still_in_status('Done').to_s).to eql '2021-10-02 00:00:00 +0000'
    end

    it 'item moved to done twice should return first time only' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-03T00:00:00+00:00')
      expect(issue.still_in_status('Done').to_s).to eql '2021-10-02 00:00:00 +0000'
    end

    it "doesn't match any" do
      issue = load_issue 'SP-10'
      expect(issue.still_in_status('NoStatus')).to be_nil
    end
  end

  context 'currently_in_status_category' do
    it 'item moved to done and then back to in progress' do
      issue = load_issue 'SP-10', board: board
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue.currently_in_status_category('finished')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue = load_issue 'SP-10', board: board
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue.currently_in_status_category('finished').to_s).to eql '2021-10-02 00:00:00 +0000'
    end
  end

  context 'still_in_status_category' do
    it 'item moved to done and then back to in progress' do
      issue = load_issue 'SP-10', board: board
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue.still_in_status_category('finished')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue = load_issue 'SP-10', board: board
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue.still_in_status_category('finished').to_s).to eql '2021-10-02 00:00:00 +0000'
    end

    it 'item moved to done twice should return first time only' do
      issue = load_issue 'SP-10', board: board
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-03T00:00:00+00:00')
      expect(issue.still_in_status_category('finished').to_s).to eql '2021-10-02 00:00:00 +0000'
    end
  end

  context 'blocked_percentage' do
    it 'should be zero if never blocked' do
      issue = empty_issue created: '2021-10-01T00:00:00+00:00'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-03T00:00:00+00:00')

      percentage = issue.blocked_percentage(
        ->(i) { i.first_time_in_status('In Progress') },
        ->(i) { i.first_time_in_status('Done') }
      )
      expect(percentage).to eq 0
    end

    it 'should handle being blocked and unblocked within the window' do
      issue = empty_issue created: '2021-10-01T00:00:00+00:00'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-02T12:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-03T12:00:00+00:00')
      issue.changes << mock_change(field: 'status',  value: 'Done',        time: '2021-10-04T00:00:00+00:00')

      percentage = issue.blocked_percentage(
        ->(i) { i.first_time_in_status('In Progress') },
        ->(i) { i.first_time_in_status('Done') }
      )
      expect(percentage).to eq 50.0
    end

    it 'should handle starting blocked and later unblocked within the window' do
      issue = empty_issue created: '2021-10-01T00:00:00+00:00'
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-01T12:00:00+00:00')
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-03T00:00:00+00:00')
      issue.changes << mock_change(field: 'status',  value: 'Done',        time: '2021-10-04T00:00:00+00:00')

      percentage = issue.blocked_percentage(
        ->(i) { i.first_time_in_status('In Progress') },
        ->(i) { i.first_time_in_status('Done') }
      )
      expect(percentage).to eq 50.0
    end

    it 'should handle blocked and unblocked before the start time' do
      issue = empty_issue created: '2021-10-01T00:00:00+00:00'
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-02T12:00:00+00:00')
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-03T00:00:00+00:00')
      issue.changes << mock_change(field: 'status',  value: 'Done',        time: '2021-10-04T00:00:00+00:00')

      percentage = issue.blocked_percentage(
        ->(i) { i.first_time_in_status('In Progress') },
        ->(i) { i.first_time_in_status('Done') }
      )
      expect(percentage).to eq 0.0
    end

    it 'should handle still being blocked at done' do
      issue = empty_issue created: '2021-10-01T00:00:00+00:00'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:00:00+00:00')
      issue.changes << mock_change(field: 'status',  value: 'Done',        time: '2021-10-04T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-05T00:00:00+00:00')

      percentage = issue.blocked_percentage(
        ->(i) { i.first_time_in_status('In Progress') },
        ->(i) { i.first_time_in_status('Done') }
      )
      expect(percentage).to eq 50.0
    end

    it 'should handle being in and out of flagged multiple times' do
      issue = empty_issue created: '2021-10-01T00:00:00+00:00'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-04T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-05T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-06T00:00:00+00:00')
      issue.changes << mock_change(field: 'status',  value: 'Done',        time: '2021-10-07T00:00:00+00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-08T00:00:00+00:00')

      percentage = issue.blocked_percentage(
        ->(i) { i.first_time_in_status('In Progress') },
        ->(i) { i.first_time_in_status('Done') }
      )
      expect(percentage).to eq 40.0
    end
  end

  context 'blocked_on_date?' do
    it 'should work when blocked and unblocked on same day' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')

      actual = [
        issue.blocked_on_date?(Date.parse('2021-10-02')),
        issue.blocked_on_date?(Date.parse('2021-10-03')),
        issue.blocked_on_date?(Date.parse('2021-10-04'))
      ]
      expect(actual).to eq [false, true, false]
    end

    it 'should still be blocked the day after' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03')

      actual = [
        issue.blocked_on_date?(Date.parse('2021-10-02')),
        issue.blocked_on_date?(Date.parse('2021-10-03')),
        issue.blocked_on_date?(Date.parse('2021-10-04'))
      ]
      expect(actual).to eq [false, true, true]
    end

    it 'should handle the case where the issue is unblocked before ever becoming blocked' do
      # Why are we testing this? Because we've seen it in production and need to ensure it doesn't
      # blow up.
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-03')

      actual = [
        issue.blocked_on_date?(Date.parse('2021-10-02')),
        issue.blocked_on_date?(Date.parse('2021-10-03')),
        issue.blocked_on_date?(Date.parse('2021-10-04'))
      ]
      expect(actual).to eq [false, false, false]
    end
  end

  context 'stalled_on_date?' do
    it 'should show stalled if the updated date is within the threshold' do
      issue = empty_issue created: '2021-10-01'
      issue.raw['fields']['updated'] = '2021-10-01T00:00:00'

      expect(issue.stalled_on_date? Date.parse('2021-12-01')).to be_truthy
      expect(issue.stalled_on_date? Date.parse('2021-10-02')).to be_falsey
    end

    it 'should be stalled after a gap' do
      issue = empty_issue created: '2021-10-01'
      issue.raw['fields']['updated'] = '2021-10-01T00:00:00'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-11-02')

      expect(issue.stalled_on_date? Date.parse('2021-11-01')).to be_truthy
      expect(issue.stalled_on_date? Date.parse('2021-11-02')).to be_falsey
    end

    it 'should be stalled before the updated time' do
      issue = empty_issue created: '2021-10-01'
      issue.raw['fields']['updated'] = '2021-11-02T00:00:00'

      expect(issue.stalled_on_date? Date.parse('2021-11-01')).to be_truthy
      expect(issue.stalled_on_date? Date.parse('2021-11-02')).to be_falsey
    end
  end

  context 'inspect' do
    it 'should return a simplified representation' do
      expect(empty_issue(created: '2021-10-01T00:00:00+00:00').inspect).to eql 'Issue("SP-1")'
    end
  end

  context 'resolutions' do
    it 'should find resolutions when they are present' do
      issue = empty_issue created: '2021-10-01T00:00:00+00:00'
      issue.changes << mock_change(field: 'status',     value: 'In Progress',  time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'resolution', value: 'Done',         time: '2021-10-03T01:00:00+00:00')
      issue.changes << mock_change(field: 'status',     value: 'In Progress',  time: '2021-10-04T02:00:00+00:00')
      issue.changes << mock_change(field: 'resolution', value: 'Done',         time: '2021-10-05T01:00:00+00:00')
      issue.changes << mock_change(field: 'status',     value: 'In Progress',  time: '2021-10-06T02:00:00+00:00')
      issue.changes << mock_change(field: 'resolution', value: 'Done',         time: '2021-10-07T01:00:00+00:00')

      expect([issue.first_resolution, issue.last_resolution]).to eq [
        to_time('2021-10-03T01:00:00+00:00'),
        to_time('2021-10-07T01:00:00+00:00')
      ]
    end

    it 'should handle the case where there are no resolutions' do
      issue = empty_issue created: '2021-10-01'
      expect([issue.first_resolution, issue.last_resolution]).to eq [nil, nil]
    end
  end

  context 'resolution' do
    it 'should return nil when not resolved' do
      issue = empty_issue created: '2021-10-01'
      expect(issue.resolution).to be_nil
    end

    it 'should work' do
      issue = empty_issue created: '2021-10-01'
      issue.raw['fields']['resolution'] = { 'name' => 'Done' }
      expect(issue.resolution).to eq 'Done'
    end
  end

  context 'created from a linked issue' do
    let(:issue) do
      Issue.new raw: {
        'id' => '10019',
        'key' => 'SP-12',
        'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/issue/10019',
        'fields' => {
          'summary' => 'Report of all events',
          'status' => {
            'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/status/10002',
            'description' => '',
            'iconUrl' => 'https =>//improvingflow.atlassian.net/',
            'name' => 'Done',
            'id' => '10002',
            'statusCategory' => {
              'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/statuscategory/3',
              'id' => 3,
              'key' => 'done',
              'colorName' => 'green',
              'name' => 'Done'
            }
          },
          'priority' => {
            'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/priority/3',
            'iconUrl' => 'https =>//improvingflow.atlassian.net/images/icons/priorities/medium.svg',
            'name' => 'Medium',
            'id' => '3'
          },
          'issuetype' => {
            'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/issuetype/10001',
            'id' => '10001',
            'description' => 'Functionality or a feature expressed as a user goal.',
            'iconUrl' => 'https =>//improvingflow.atlassian.net/rest/api/2/universal_avatar/view/type/' \
              'issuetype/avatar/10315?size=medium',
            'name' => 'Story',
            'subtask' => false,
            'avatarId' => 10_315,
            'hierarchyLevel' => 0
          }
        }
      },
      board: sample_board
    end

    it 'gets key' do
      expect(issue.key).to eql 'SP-12'
    end

    it 'gets type' do
      expect(issue.type).to eql 'Story'
    end

    it 'gets key' do
      expect(issue.summary).to eql 'Report of all events'
    end
  end

  context 'status' do
    it 'should work' do
      expect(load_issue('SP-1').status).to eql(
        Status.new(name: 'In Progress', id: 3, category_name: 'In Progress', category_id: 4)
      )
    end
  end

  context 'last_activity' do
    let(:issue) { empty_issue created: '2020-01-01' }

    it 'should handle no activity, ever' do
      expect(issue.last_activity now: to_time('2001-01-01')).to be_nil
    end

    it 'should pick most recent change' do
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-02')
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-03')
      expect(issue.last_activity now: to_time('2021-01-01')).to eq to_time('2020-01-03')
    end

    it 'should handle subtask with no changes' do
      subtask = empty_issue created: '2020-01-02'
      issue.subtasks << subtask
      expect(issue.last_activity now: to_time('2021-02-01')).to eq to_time('2020-01-02')
    end

    it 'should handle multiple subtasks, each with changes' do
      subtask1 = empty_issue created: '2020-01-02'
      subtask1.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-03')
      issue.subtasks << subtask1

      subtask2 = empty_issue created: '2020-01-02'
      subtask2.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-04')
      issue.subtasks << subtask2

      expect(issue.last_activity now: to_time('2021-01-01')).to eq to_time('2020-01-04')
    end

    it 'should handle no activity on the subtask but activity on the main issue' do
      subtask = empty_issue created: '2020-01-01'
      issue.subtasks << subtask

      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-02')

      expect(issue.last_activity now: to_time('2001-01-01')).to be_nil
    end
  end
end
