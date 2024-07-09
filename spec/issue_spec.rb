# frozen_string_literal: true

require './spec/spec_helper'

describe Issue do
  let(:exporter) { Exporter.new }
  let(:target_path) { 'spec/testdata/' }
  let(:project_config) do
    ProjectConfig.new exporter: exporter, target_path: target_path, jira_config: nil, block: nil
  end
  let(:board) do
    board = sample_board
    board.project_config = project_config
    statuses = board.possible_statuses
    statuses.clear
    statuses << Status.new(name: 'Backlog', id: 1, category_name: 'ready', category_id: 2)
    statuses << Status.new(name: 'Selected for Development', id: 3, category_name: 'ready', category_id: 4)
    statuses << Status.new(name: 'In Progress', id: 5, category_name: 'in-flight', category_id: 6)
    statuses << Status.new(name: 'Review', id: 7, category_name: 'in-flight', category_id: 8)
    statuses << Status.new(name: 'Done', id: 9, category_name: 'finished', category_id: 10)
    board
  end
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:issue2) { load_issue 'SP-2', board: board }
  let(:issue10) { load_issue 'SP-10', board: board }

  it 'gets key' do
    expect(issue2.key).to eql 'SP-2'
  end

  it 'gets url' do
    expect(issue2.url).to eql 'https://improvingflow.atlassian.net/browse/SP-2'
  end

  it 'cannot fabricate url' do
    issue2.board.raw['self'] = nil
    expect { issue2.url }.to raise_error 'Cannot parse self: nil'
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
    issue = described_class.new raw: raw, board: sample_board
    expect([issue.created, issue.updated]).to eq [
      Time.parse('2021-08-29T18:00:00+00:00'),
      Time.parse('2021-09-29T18:00:00+00:00')
    ]
  end

  context 'initialize' do
    it 'includes issue key when an exception happens' do
      raw = {
        'key' => 'SP-1',
        'changelog' => { 'histories' => [] }
      }
      expect { described_class.new raw: raw, board: sample_board }.to raise_error(
        'Unable to initialize SP-1'
      )
    end
  end

  context 'load_history_into_changes' do
    it 'continues even when the history does not have items (seen in prod)' do
      raw = {
        'key' => 'SP-1',
        'changelog' => { 'histories' => [{ 'created' => '2021-08-29T18:00:00+00:00' }] },
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
      issue = described_class.new raw: raw, board: sample_board
      expect([issue.created, issue.updated]).to eq [
        Time.parse('2021-08-29T18:00:00+00:00'),
        Time.parse('2021-09-29T18:00:00+00:00')
      ]
    end
  end

  context 'changes' do
    it 'gets simple history with a single status' do
      expect(issue2.changes).to eq [
        mock_change(field: 'status', value: 'Backlog', time: '2021-06-18T18:41:37.804+0000'),
        mock_change(field: 'priority', value: 'Medium', time: '2021-06-18T18:41:37.804+0000'),
        mock_change(field: 'status', value: 'Selected for Development', time: '2021-06-18T18:43:38+00:00')
      ]
    end

    it 'gets complex history with a mix of field types' do
      expect(issue10.changes).to eq [
        mock_change(field: 'status',     value: 'Backlog',                  time: '2021-06-18T18:42:52.754+0000'),
        mock_change(field: 'priority',   value: 'Medium',                   time: '2021-06-18T18:42:52.754+0000'),
        mock_change(field: 'status',     value: 'Selected for Development', time: '2021-08-29T18:06:28+0000'),
        mock_change(field: 'Rank',       value: 'Ranked higher',            time: '2021-08-29T18:06:28+0000'),
        mock_change(field: 'priority',   value: 'Highest',                  time: '2021-08-29T18:06:43+0000'),
        mock_change(field: 'status',     value: 'In Progress',              time: '2021-08-29T18:06:55+0000'),
        mock_change(field: 'status',     value: 'Selected for Development', time: '2021-09-06T04:33:11+0000'),
        mock_change(field: 'Flagged',    value: 'Impediment',               time: '2021-09-06T04:33:30+0000'),
        mock_change(field: 'priority',   value: 'Medium',                   time: '2021-09-06T04:33:50+0000'),
        mock_change(field: 'Flagged',    value: '',                         time: '2021-09-06T04:33:55+0000'),
        mock_change(field: 'status',     value: 'In Progress',              time: '2021-09-06T04:34:02+0000'),
        mock_change(field: 'status',     value: 'Review',                   time: '2021-09-06T04:34:21+0000'),
        mock_change(field: 'status',     value: 'Done',                     time: '2021-09-06T04:34:26+0000'),
        mock_change(field: 'resolution', value: 'Done',                     time: '2021-09-06T04:34:26+0000')
       ]
    end

    it "defaults the first status if there really hasn't been any yet" do
      issue = empty_issue created: '2021-08-29T18:00:00+00:00'
      expect(issue.changes).to eq [
        mock_change(field: 'status', value: 'Backlog', time: '2021-08-29T18:00:00+00:00')
      ]
    end
  end

  context 'first_time_in_status' do
    it 'first time in status' do
      expect(time_to_s issue10.first_time_in_status('In Progress')).to eql '2021-08-29 18:06:55 +0000'
    end

    it "first time in status that doesn't match any" do
      expect(issue10.first_time_in_status('NoStatus')).to be_nil
    end
  end

  context 'first_time_not_in_status' do
    it 'first time not in status' do
      expect(time_to_s issue10.first_time_not_in_status('Backlog')).to eql '2021-08-29 18:06:28 +0000'
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
      issue = described_class.new raw: raw, board: sample_board
      expect(issue.first_time_not_in_status('BrandNew!')).to be_nil
    end
  end

  context 'first_time_in_or_right_of_column' do
    it 'fails for invalid column name' do
      expect { issue1.first_time_in_or_right_of_column 'NoSuchColumn' }.to raise_error(
        'No visible column with name: "NoSuchColumn" Possible options are: "Ready", "In Progress", "Review", "Done"'
      )
    end

    it 'works for happy path' do
      # The second column is called "In Progress" and it's only mapped to status 3
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'A', value_id: 1, time: '2021-06-18')
      issue1.changes << mock_change(field: 'status', value: 'B', value_id: 3, time: '2021-07-18')

      expect(issue1.first_time_in_or_right_of_column 'In Progress').to eq to_time('2021-07-18')
    end

    it 'returns nil when no matches' do
      # The second column is called "In Progress" and it's only mapped to status 3
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'A', value_id: 1, time: '2021-06-18')

      expect(issue1.first_time_in_or_right_of_column 'In Progress').to be_nil
    end
  end

  context 'still_in_or_right_of_column' do
    it 'works for happy path' do
      # The second column is called "In Progress" and it's only mapped to status 3
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'A', value_id: 1, time: '2021-06-01')
      issue1.changes << mock_change(field: 'status', value: 'B', value_id: 3, time: '2021-06-02')
      issue1.changes << mock_change(field: 'status', value: 'A', value_id: 1, time: '2021-06-03')
      issue1.changes << mock_change(field: 'status', value: 'B', value_id: 3, time: '2021-06-04')
      issue1.changes << mock_change(field: 'status', value: 'B', value_id: 3, time: '2021-06-05')

      expect(issue1.still_in_or_right_of_column 'In Progress').to eq to_time('2021-06-04')
    end
  end

  context 'first_time_in_status_category' do
    it 'first time in status category' do
      issue10.board.possible_statuses << Status.new(
        name: 'Done',
        id: 1,
        category_name: 'finished',
        category_id: 2
      )

      expect(time_to_s issue10.first_time_in_status_category('finished')).to eq '2021-09-06 04:34:26 +0000'
    end
  end

  context 'first_status_change_after_created' do
    it "finds first time for any status change - created doesn't count as status change" do
      expect(time_to_s issue10.first_status_change_after_created).to eql '2021-08-29 18:06:28 +0000'
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
      issue = described_class.new raw: raw, board: sample_board
      expect(issue.first_status_change_after_created).to be_nil
    end
  end

  context 'currently_in_status' do
    it 'item moved to done and then back to in progress' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue10.currently_in_status('Done')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue10.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue10.currently_in_status('Done').to_s).to eql '2021-10-02 00:00:00 +0000'
    end
  end

  context 'still_in_status' do
    it 'item moved to done and then back to in progress' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue10.still_in_status('Done')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue10.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue10.still_in_status('Done').to_s).to eql '2021-10-02 00:00:00 +0000'
    end

    it 'item moved to done twice should return first time only' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue10.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      issue10.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-03T00:00:00+00:00')
      expect(issue10.still_in_status('Done').to_s).to eql '2021-10-02 00:00:00 +0000'
    end

    it "doesn't match any" do
      expect(issue10.still_in_status('NoStatus')).to be_nil
    end
  end

  context 'currently_in_status_category' do
    it 'item moved to done and then back to in progress' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue10.currently_in_status_category('finished')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue10.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue10.currently_in_status_category('finished').to_s).to eql '2021-10-02 00:00:00 +0000'
    end
  end

  context 'still_in_status_category' do
    it 'item moved to done and then back to in progress' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue10.still_in_status_category('finished')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue10.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue10.still_in_status_category('finished').to_s).to eql '2021-10-02 00:00:00 +0000'
    end

    it 'item moved to done twice should return first time only' do
      issue10.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue10.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      issue10.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-03T00:00:00+00:00')
      expect(issue10.still_in_status_category('finished').to_s).to eql '2021-10-02 00:00:00 +0000'
    end
  end

  context 'blocked_stalled_changes' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }
    let(:settings) do
      {
        'blocked_statuses' => %w[Blocked Blocked2],
        'stalled_statuses' => %w[Stalled Stalled2],
        'blocked_link_text' => ['is blocked by'],
        'stalled_threshold_days' => 5
      }
    end

    it 'handles never blocked' do
      issue = empty_issue created: '2021-10-01'
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-05')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-05'))
      ]
    end

    it 'handles flagged and unflagged' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-05')).to eq [
        BlockedStalledChange.new(flagged: 'Blocked', time: to_time('2021-10-03T00:01:00')),
        BlockedStalledChange.new(time: to_time('2021-10-03T00:02:00')),
        BlockedStalledChange.new(time: to_time('2021-10-05'))
      ]
    end

    it 'handles contiguous blocked status' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'status',  value: 'Blocked', time: '2021-10-03')
      issue.changes << mock_change(field: 'status',  value: 'Blocked2', time: '2021-10-04')
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-05')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-06')).to eq [
        BlockedStalledChange.new(status: 'Blocked', time: to_time('2021-10-03')),
        BlockedStalledChange.new(status: 'Blocked2', time: to_time('2021-10-04')),
        BlockedStalledChange.new(time: to_time('2021-10-05')),
        BlockedStalledChange.new(time: to_time('2021-10-06'))
      ]
    end

    it 'handles blocked statuses' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'status',  value: 'Blocked', time: '2021-10-03')
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-04')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-06')).to eq [
        BlockedStalledChange.new(status: 'Blocked', time: to_time('2021-10-03')),
        BlockedStalledChange.new(time: to_time('2021-10-04')),
        BlockedStalledChange.new(time: to_time('2021-10-06'))
      ]
    end

    it 'handles blocked on issues' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(
        field: 'Link', value: 'This issue is blocked by SP-10', time: '2021-10-02'
      )
      issue.changes << mock_change(
        field: 'Link', value: nil, old_value: 'This issue is blocked by SP-10', time: '2021-10-03'
      )
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-04')).to eq [
        BlockedStalledChange.new(blocking_issue_keys: ['SP-10'], time: to_time('2021-10-02')),
        BlockedStalledChange.new(time: to_time('2021-10-03')),
        BlockedStalledChange.new(time: to_time('2021-10-04'))
      ]
    end

    it 'handles stalled for inactivity' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(
        field: 'status', value: 'Doing', time: '2021-10-02'
      )
      issue.changes << mock_change(
        field: 'status', value: 'Doing2', time: '2021-10-08'
      )
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-10')).to eq [
        BlockedStalledChange.new(stalled_days: 6, time: to_time('2021-10-02T01:00:00')),
        BlockedStalledChange.new(time: to_time('2021-10-08')),
        BlockedStalledChange.new(time: to_time('2021-10-10'))
      ]
    end

    it 'handles contiguous stalled status' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'status',  value: 'Stalled', time: '2021-10-03')
      issue.changes << mock_change(field: 'status',  value: 'Stalled2', time: '2021-10-04')
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-05')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-06')).to eq [
        BlockedStalledChange.new(status: 'Stalled', status_is_blocking: false, time: to_time('2021-10-03')),
        BlockedStalledChange.new(status: 'Stalled2', status_is_blocking: false, time: to_time('2021-10-04')),
        BlockedStalledChange.new(time: to_time('2021-10-05')),
        BlockedStalledChange.new(time: to_time('2021-10-06'))
      ]
    end

    it 'handles stalled statuses' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'status',  value: 'Stalled', time: '2021-10-03')
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-04')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-06')).to eq [
        BlockedStalledChange.new(status: 'Stalled', status_is_blocking: false, time: to_time('2021-10-03')),
        BlockedStalledChange.new(time: to_time('2021-10-04')),
        BlockedStalledChange.new(time: to_time('2021-10-06'))
      ]
    end

    it 'does not report stalled if subtasks were active through the period' do
      # The main issue has activity on the 2nd and again on the 8th. If we don't take subtasks
      # into account then we'd expect it to show stalled between those dates. Given that we
      # should consider subtasks, it should show nothing stalled through the period.

      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(
        field: 'status', value: 'Doing', time: '2021-10-02'
      )
      issue.changes << mock_change(
        field: 'status', value: 'Doing2', time: '2021-10-08'
      )

      subtask = empty_issue created: '2021-10-01'
      subtask.changes << mock_change(
        field: 'status', value: 'Doing', time: '2021-10-05'
      )
      issue.subtasks << subtask

      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-10')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-10'))
      ]
    end

    it 'splits stalled into sections if subtasks were active in between' do
      # The full range is 1st to 12th with subtask activity on the 5th. The only
      # stalled section in here is 5-12.
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(
        field: 'status', value: 'Doing', time: '2021-10-02'
      )
      issue.changes << mock_change(
        field: 'status', value: 'Doing2', time: '2021-10-12'
      )

      subtask = empty_issue created: '2021-10-01'
      subtask.changes << mock_change(
        field: 'status', value: 'Doing', time: '2021-10-05'
      )
      issue.subtasks << subtask

      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-13')).to eq [
        BlockedStalledChange.new(stalled_days: 7, time: to_time('2021-10-05T01:00:00')),
        BlockedStalledChange.new(time: to_time('2021-10-12')),
        BlockedStalledChange.new(time: to_time('2021-10-13'))
      ]
    end

    it 'ignores the final artificial change for the purposes of stalled' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(
        field: 'status', value: 'Doing', time: '2021-10-02'
      )
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-08')).to eq [
        BlockedStalledChange.new(stalled_days: 6, time: to_time('2021-10-02T01:00:00')),
        BlockedStalledChange.new(stalled_days: 6, time: to_time('2021-10-08T00:00:00'))
      ]
    end

    it 'notices if blocked_statuses is a string' do
      settings['blocked_statuses'] = ''
      expect { issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-08') }
        .to raise_error 'blocked_statuses("") and stalled_statuses(["Stalled", "Stalled2"]) must both be arrays'
    end

    it 'notices if stalled_statuses is a string' do
      settings['stalled_statuses'] = ''
      expect { issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-08') }
        .to raise_error 'blocked_statuses(["Blocked", "Blocked2"]) and stalled_statuses("") must both be arrays'
    end
  end

  context 'blocked_stalled_by_date' do
    it 'handles no changes' do
      issue = empty_issue created: '2021-10-01', board: board
      actual = issue.blocked_stalled_by_date date_range: to_date('2021-10-02')..to_date('2021-10-04')
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-10-02') => :active,
        to_date('2021-10-03') => :active,
        to_date('2021-10-04') => :active
      })
    end

    it 'tracks blocked over multiple days' do
      issue = empty_issue created: '2021-10-01', board: board
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')

      actual = issue.blocked_stalled_by_date date_range: to_date('2021-10-02')..to_date('2021-10-04')
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-10-02') => :active,
        to_date('2021-10-03') => :blocked,
        to_date('2021-10-04') => :blocked
      })
    end

    it 'tracks blocked then unblocked' do
      issue = empty_issue created: '2021-10-01', board: board
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')

      actual = issue.blocked_stalled_by_date date_range: to_date('2021-10-02')..to_date('2021-10-04')
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-10-02') => :active,
        to_date('2021-10-03') => :blocked,
        to_date('2021-10-04') => :active
      })
    end

    it 'tracks blocked then stalled then active' do
      issue = empty_issue created: '2021-08-01', board: board
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-08-02')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')

      actual = issue.blocked_stalled_by_date date_range: to_date('2021-10-02')..to_date('2021-10-04')
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-10-02') => :active,
        to_date('2021-10-03') => :blocked,
        to_date('2021-10-04') => :active
      })
    end
  end

  context 'inspect' do
    it 'returns a simplified representation' do
      expect(empty_issue(created: '2021-10-01T00:00:00+00:00').inspect).to eql 'Issue("SP-1")'
    end
  end

  context 'resolutions' do
    it 'finds resolutions when they are present' do
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

    it 'handles the case where there are no resolutions' do
      issue = empty_issue created: '2021-10-01'
      expect([issue.first_resolution, issue.last_resolution]).to eq [nil, nil]
    end
  end

  context 'resolution' do
    it 'returns nil when not resolved' do
      issue = empty_issue created: '2021-10-01'
      expect(issue.resolution).to be_nil
    end

    it 'returns resolution' do
      issue = empty_issue created: '2021-10-01'
      issue.raw['fields']['resolution'] = { 'name' => 'Done' }
      expect(issue.resolution).to eq 'Done'
    end
  end

  context 'created from a linked issue' do
    let(:issue) do
      described_class.new raw: {
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

    it 'gets summary' do
      expect(issue.summary).to eql 'Report of all events'
    end
  end

  context 'status' do
    it 'returns status' do
      expect(load_issue('SP-1').status).to eql(
        Status.new(name: 'In Progress', id: 3, category_name: 'In Progress', category_id: 4)
      )
    end
  end

  context 'last_activity' do
    let(:issue) { empty_issue created: '2020-01-01' }

    it 'handles no activity, ever' do
      expect(issue.last_activity now: to_time('2001-01-01')).to be_nil
    end

    it 'picks most recent change' do
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-02')
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-03')
      expect(issue.last_activity now: to_time('2021-01-01')).to eq to_time('2020-01-03')
    end

    it 'handles subtask with no changes' do
      subtask = empty_issue created: '2020-01-02'
      issue.subtasks << subtask
      expect(issue.last_activity now: to_time('2021-02-01')).to eq to_time('2020-01-02')
    end

    it 'handles multiple subtasks, each with changes' do
      subtask1 = empty_issue created: '2020-01-02'
      subtask1.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-03')
      issue.subtasks << subtask1

      subtask2 = empty_issue created: '2020-01-02'
      subtask2.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-04')
      issue.subtasks << subtask2

      expect(issue.last_activity now: to_time('2021-01-01')).to eq to_time('2020-01-04')
    end

    it 'handles no activity on the subtask but activity on the main issue' do
      subtask = empty_issue created: '2020-01-01'
      issue.subtasks << subtask

      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2020-01-02')

      expect(issue.last_activity now: to_time('2001-01-01')).to be_nil
    end
  end

  context 'parent_link' do
    let(:issue) { empty_issue created: '2020-01-01' }

    it 'returns nil when no parent found' do
      expect(issue.parent_key).to be_nil
    end

    it 'gets the new parent link' do
      issue.raw['fields']['parent'] = {
        'id' => '10097',
        'key' => 'ABC-1',
        'self' => 'https://{your_jira_site}.com/rest/api/3/issue/10097',
        'fields' => {}
      }
      expect(issue.parent_key).to eq 'ABC-1'
    end

    it 'gets the epic link' do
      # Note that I haven't seen this in production yet but it's in the documentation at:
      # https://community.developer.atlassian.com/t/deprecation-of-the-epic-link-parent-link-and-other-related-fields-in-rest-apis-and-webhooks/54048

      issue.raw['fields']['epic'] = {
        'id' => 10_001,
        'key' => 'ABC-1',
        'self' => 'https://{your_jira_site}/rest/agile/1.0/epic/10001',
        'name' => 'epic',
        'summary' => 'epic',
        'color' => {
            'key' => 'color_1'
        },
        'done' => false
      }
      expect(issue.parent_key).to eq 'ABC-1'
    end

    context 'custom fields' do
      it 'determines multiple custom fields from settings and get the parent from there' do
        project_config.settings['customfield_parent_links'] = %w[customfield_1 customfield_2]
        issue.board.project_config = project_config
        issue.raw['fields']['customfield_2'] = 'ABC-2'
        expect(issue.parent_key).to eq 'ABC-2'
      end

      it 'determines single custom fields from settings and get the parent from there' do
        project_config.settings['customfield_parent_links'] = 'customfield_1'
        issue.board.project_config = project_config
        issue.raw['fields']['customfield_1'] = 'ABC-1'
        expect(issue.parent_key).to eq 'ABC-1'
      end
    end
  end

  context 'expedited?' do
    let(:issue) { empty_issue created: '2020-01-01' }

    it 'no board' do
      expect(empty_issue(created: '2020-01-01', board: nil)).not_to be_expedited
    end

    it 'no priority set' do
      expect(issue).not_to be_expedited
    end

    it 'priority set but not expedited' do
      issue.raw['fields']['priority'] = 'high'
      expect(issue).not_to be_expedited
    end

    it 'priority set to expedited' do
      issue.raw['fields']['priority'] = { 'name' => 'high' }
      issue.board.expedited_priority_names = ['high']
      expect(issue).to be_expedited
    end
  end

  context 'expedited_on_date?' do
    it 'returns false if no board was set' do
      issue = empty_issue created: '2021-10-01', board: nil
      expect(issue).not_to be_expedited_on_date(to_date('2021-10-02'))
    end

    it 'works when expedited turns on and off on same day' do
      issue = empty_issue created: '2021-10-01'
      issue.board.expedited_priority_names = ['high']

      issue.changes << mock_change(field: 'priority', value: 'high', time: '2021-10-03T00:01:00')
      issue.changes << mock_change(field: 'priority', value: '',     time: '2021-10-03T00:02:00')

      actual = [
        issue.expedited_on_date?(to_date('2021-10-02')),
        issue.expedited_on_date?(to_date('2021-10-03')),
        issue.expedited_on_date?(to_date('2021-10-04'))
      ]
      expect(actual).to eq [false, true, false]
    end

    it 'works when one expedite follows another' do
      issue = empty_issue created: '2021-10-01'
      issue.board.expedited_priority_names = %w[high higher]

      issue.changes << mock_change(field: 'priority', value: 'high', time: '2021-10-02T00:01:00')
      issue.changes << mock_change(field: 'priority', value: 'higher', time: '2021-10-03T00:02:00')
      issue.changes << mock_change(field: 'priority', value: '', time: '2021-10-03T00:04:00')

      actual = [
        issue.expedited_on_date?(to_date('2021-10-01')),
        issue.expedited_on_date?(to_date('2021-10-02')),
        issue.expedited_on_date?(to_date('2021-10-03')),
        issue.expedited_on_date?(to_date('2021-10-04'))
      ]
      expect(actual).to eq [false, true, true, false]
    end

    it 'works when still expedited at end of data' do
      issue = empty_issue created: '2021-10-01'
      issue.board.expedited_priority_names = %w[high higher]

      issue.changes << mock_change(field: 'priority', value: 'high', time: '2021-10-02T00:01:00')

      actual = [
        issue.expedited_on_date?(to_date('2021-10-01')),
        issue.expedited_on_date?(to_date('2021-10-02'))
      ]
      expect(actual).to eq [false, true]
    end
  end

  context 'sorting' do
    it 'sorts when project key is the same and the numbers are different' do
      a = empty_issue(key: 'SP-1', created: '2022-01-01')
      b = empty_issue(key: 'SP-2', created: '2022-01-01')
      expect([b, a].sort.collect(&:key)).to eq %w[SP-1 SP-2]
    end

    it 'sorts when project keys are different and the numbers are same' do
      a = empty_issue(key: 'SPA-1', created: '2022-01-01')
      b = empty_issue(key: 'SPB-2', created: '2022-01-01')
      expect([b, a].sort.collect(&:key)).to eq %w[SPA-1 SPB-2]
    end
  end

  context 'author' do
    it 'returns empty string when author section is missing' do
      issue1.raw['fields']['creator'] = nil
      expect(issue1.author).to eq ''
    end

    it 'returns author' do
      expect(issue1.author).to eq 'Mike Bowler'
    end
  end

  context 'dump' do
    it 'dumps simple issue' do
      expect(issue1.dump).to eq <<~TEXT
        SP-1 (Story): Create new draft event
          [change] 2021-06-18 18:41:29 +0000 [status] "Backlog" (Mike Bowler) <<artificial entry>>
          [change] 2021-06-18 18:41:29 +0000 [priority] "Medium" (Mike Bowler) <<artificial entry>>
          [change] 2021-06-18 18:43:34 +0000 [status] "Backlog" -> "Selected for Development" (Mike Bowler)
          [change] 2021-06-18 18:44:21 +0000 [status] "Selected for Development" -> "In Progress" (Mike Bowler)
          [change] 2021-08-29 18:04:39 +0000 [Flagged] "Impediment" (Mike Bowler)
      TEXT
    end

    it 'dumps complex issue' do
      fields = issue1.raw['fields']
      fields['assignee'] = { 'name' => 'Barney Rubble', 'emailAddress' => 'barney@rubble.com' }
      fields['issuelinks'] = [
        {
          'type' => {
            'inward' => 'Clones'
          },
          'inwardIssue' => {
            'key' => 'ABC123'
          }
        },
        {
          'type' => {
            'outward' => 'Cloned by'
          },
          'outwardIssue' => {
            'key' => 'ABC456'
          }
        }
      ]
      expect(issue1.dump).to eq <<~TEXT
        SP-1 (Story): Create new draft event
          [assignee] "Barney Rubble" <barney@rubble.com>
          [link] Clones ABC123
          [link] Cloned by ABC456
          [change] 2021-06-18 18:41:29 +0000 [status] "Backlog" (Mike Bowler) <<artificial entry>>
          [change] 2021-06-18 18:41:29 +0000 [priority] "Medium" (Mike Bowler) <<artificial entry>>
          [change] 2021-06-18 18:43:34 +0000 [status] "Backlog" -> "Selected for Development" (Mike Bowler)
          [change] 2021-06-18 18:44:21 +0000 [status] "Selected for Development" -> "In Progress" (Mike Bowler)
          [change] 2021-08-29 18:04:39 +0000 [Flagged] "Impediment" (Mike Bowler)
      TEXT
    end
  end

  context 'created' do
    it "doesn't blow up if created is missing" do # Seen in production
      issue1.raw['fields']['created'] = nil
      expect(issue1.created).to be_nil
    end
  end

  context 'key_as_i' do
    it 'returns when valid' do
      expect(issue1.key_as_i).to eq 1
    end

    it 'returns 0 when invalid' do
      issue1.raw['key'] = 'ABC'
      expect(issue1.key_as_i).to eq 0
    end
  end

  context 'component_names' do
    it 'returns empty when there are none' do
      issue1.raw['fields']['components'] = nil
      expect(issue1.component_names).to be_empty
    end

    it 'returns names' do
      issue1.raw['fields']['components'] = [
        { 'name' => 'One' }
      ]
      expect(issue1.component_names).to eq ['One']
    end
  end

  it 'blows up if status can\'t be found for find_status_by_name' do
    expect { issue1.find_status_by_name 'undefined_status_name' }.to raise_error(
      'Status name "undefined_status_name" for issue SP-1 not found in ["Backlog", ' \
        '"Selected for Development", "In Progress", "Review", "Done"]'
    )
  end
end
