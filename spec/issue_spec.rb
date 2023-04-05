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
    issue2.raw['self'] = nil
    expect(issue2.url).to be_nil
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
    end

    it "should default the first status if there really hasn't been any yet" do
      issue = empty_issue created: '2021-08-29T18:00:00+00:00'
      expect(issue.changes).to eq [
        mock_change(field: 'status', value: 'Backlog', time: '2021-08-29T18:00:00+00:00')
      ]
    end
  end

  context 'first_time_in_status' do
    it 'first time in status' do
      expect(issue10.first_time_in_status('In Progress').to_s).to eql '2021-08-29 18:06:55 +0000'
    end

    it "first time in status that doesn't match any" do
      expect(issue10.first_time_in_status('NoStatus')).to be_nil
    end
  end

  context 'first_time_not_in_status' do
    it 'first time not in status' do
      expect(issue10.first_time_not_in_status('Backlog').to_s).to eql '2021-08-29 18:06:28 +0000'
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
  end

  context 'first_time_in_or_right_of_column' do
    it 'should fail for invalid column name' do
      expect { issue1.first_time_in_or_right_of_column 'NoSuchColumn' }.to raise_error(
        'No visible column with name: "NoSuchColumn" Possible options are: "Ready", "In Progress", "Review", "Done"'
      )
    end

    it 'should work for happy path' do
      # The second column is called "In Progress" and it's only mapped to status 3
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'A', value_id: 1, time: '2021-06-18')
      issue1.changes << mock_change(field: 'status', value: 'B', value_id: 3, time: '2021-07-18')

      expect(issue1.first_time_in_or_right_of_column 'In Progress').to eq to_time('2021-07-18')
    end

    it 'should return nil when no matches' do
      # The second column is called "In Progress" and it's only mapped to status 3
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'A', value_id: 1, time: '2021-06-18')

      expect(issue1.first_time_in_or_right_of_column 'In Progress').to be_nil
    end
  end

  context 'still_in_or_right_of_column' do
    it 'should work for happy path' do
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

  context 'first_status_change_after_created' do
    it "first time for any status change - created doesn't count as status change" do
      expect(issue10.first_status_change_after_created.to_s).to eql '2021-08-29 18:06:28 +0000'
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

      expect(issue10.first_time_in_status_category('finished').to_s).to eq '2021-09-06 04:34:26 +0000'
    end
  end

  context 'first_status_change_after_created' do
    it 'first status change after created' do
      expect(issue10.first_status_change_after_created.to_s).to eql '2021-08-29 18:06:28 +0000'
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

  context 'flagged_on_date?' do
    it 'should work when blocked and unblocked on same day' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
      issue.changes << mock_change(field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')

      actual = [
        issue.flagged_on_date?(to_date('2021-10-02')),
        issue.flagged_on_date?(to_date('2021-10-03')),
        issue.flagged_on_date?(to_date('2021-10-04'))
      ]
      expect(actual).to eq [false, true, false]
    end

    it 'should still be blocked the day after' do
      issue = empty_issue created: '2021-10-01'
      issue.changes << mock_change(field: 'status',  value: 'In Progress', time: '2021-10-02')
      issue.changes << mock_change(field: 'Flagged', value: 'Blocked',     time: '2021-10-03')

      actual = [
        issue.flagged_on_date?(to_date('2021-10-02')),
        issue.flagged_on_date?(to_date('2021-10-03')),
        issue.flagged_on_date?(to_date('2021-10-04'))
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
        issue.flagged_on_date?(to_date('2021-10-02')),
        issue.flagged_on_date?(to_date('2021-10-03')),
        issue.flagged_on_date?(to_date('2021-10-04'))
      ]
      expect(actual).to eq [false, false, false]
    end
  end

  context 'in_blocked_status_on_date?' do
    let(:blocked_status) { Status.new(name: 'Blocked', id: 20_000, category_name: 'foo', category_id: 20_001) }
    let(:in_progress_status) { board.possible_statuses.find { |s| s.name == 'In Progress' } }

    it 'should return false if no blocked statuses specified' do
      date = to_date('2021-10-01')
      issue = empty_issue created: date
      issue.board.possible_statuses << blocked_status

      expect(issue.in_blocked_status_on_date? date, blocked_status_names: %w[Blocked]).to be_falsey
    end

    it 'should work when blocked and unblocked on same day' do
      issue = empty_issue created: '2021-10-01'
      issue.board.possible_statuses << blocked_status
      issue.changes << mock_change(field: 'status', value: in_progress_status, time: '2021-10-02')
      issue.changes << mock_change(
        field: 'status', value: blocked_status, old_value: in_progress_status, time: '2021-10-03T00:01:00'
      )
      issue.changes << mock_change(
        field: 'status', value: in_progress_status, old_value: blocked_status, time: '2021-10-03T00:02:00'
      )

      actual = [
        issue.in_blocked_status_on_date?(to_date('2021-10-02'), blocked_status_names: %w[Blocked]),
        issue.in_blocked_status_on_date?(to_date('2021-10-03'), blocked_status_names: %w[Blocked]),
        issue.in_blocked_status_on_date?(to_date('2021-10-04'), blocked_status_names: %w[Blocked])
      ]
      expect(actual).to eq [false, true, false]
    end

    it 'should still be blocked the day after' do
      issue = empty_issue created: '2021-10-01'
      issue.board.possible_statuses << blocked_status
      issue.changes << mock_change(
        field: 'status', value: in_progress_status, time: '2021-10-02'
      )
      issue.changes << mock_change(
        field: 'status', value: blocked_status, old_value: in_progress_status, time: '2021-10-03'
      )

      actual = [
        issue.in_blocked_status_on_date?(to_date('2021-10-02'), blocked_status_names: %w[Blocked]),
        issue.in_blocked_status_on_date?(to_date('2021-10-03'), blocked_status_names: %w[Blocked]),
        issue.in_blocked_status_on_date?(to_date('2021-10-04'), blocked_status_names: %w[Blocked])
      ]
      expect(actual).to eq [false, true, true]
    end
  end

  context 'stalled_on_date?' do
    it 'should show stalled if the updated date is within the threshold' do
      issue = empty_issue created: '2021-10-01'
      issue.raw['fields']['updated'] = '2021-10-01T00:00:00+00:00'

      expect(issue.stalled_on_date? to_date('2021-12-01')).to be_truthy
      expect(issue.stalled_on_date? to_date('2021-10-02')).to be_falsey
    end

    it 'should be stalled after a gap' do
      issue = empty_issue created: '2021-10-01'
      issue.raw['fields']['updated'] = '2021-10-01T00:00:00+00:00'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-11-02')

      expect(issue.stalled_on_date? to_date('2021-11-01')).to be_truthy
      expect(issue.stalled_on_date? to_date('2021-11-02')).to be_falsey
    end

    it 'should be stalled before the updated time' do
      issue = empty_issue created: '2021-10-01'
      issue.raw['fields']['updated'] = '2021-11-02T00:00:00+00:00'

      expect(issue.stalled_on_date? to_date('2021-11-01')).to be_truthy
      expect(issue.stalled_on_date? to_date('2021-11-02')).to be_falsey
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

  context 'parent_link' do
    let(:issue) { empty_issue created: '2020-01-01' }

    it 'should return nil when no parent found' do
      expect(issue.parent_key).to be_nil
    end

    it 'should get the new parent link' do
      issue.raw['fields']['parent'] = {
        'id' => '10097',
        'key' => 'ABC-1',
        'self' => 'https://{your_jira_site}.com/rest/api/3/issue/10097',
        'fields' => {
        }
      }
      expect(issue.parent_key).to eq 'ABC-1'
    end

    it 'should get the epic link' do
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
      it 'should determine multiple custom fields from settings and get the parent from there' do
        project_config.settings['customfield_parent_links'] = %w[customfield_1 customfield_2]
        issue.board.project_config = project_config
        issue.raw['fields']['customfield_2'] = 'ABC-2'
        expect(issue.parent_key).to eq 'ABC-2'
      end

      it 'should determine single custom fields from settings and get the parent from there' do
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
      expect(empty_issue(created: '2020-01-01', board: nil).expedited?).to be_falsey
    end

    it 'no priority set' do
      expect(issue.expedited?).to be_falsey
    end

    it 'priority set but not expedited' do
      issue.raw['fields']['priority'] = 'high'
      expect(issue.expedited?).to be_falsey
    end

    it 'priority set to expedited' do
      issue.raw['fields']['priority'] = { 'name' => 'high' }
      issue.board.expedited_priority_names = ['high']
      expect(issue.expedited?).to be_truthy
    end
  end

  context 'expedited_on_date?' do
    it 'should return false if no board was set' do
      issue = empty_issue created: '2021-10-01', board: nil
      expect(issue.expedited_on_date? to_date('2021-10-02')).to be_falsey
    end

    it 'should work when expedited turns on and off on same day' do
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

    it 'should work when one expedite follows another' do
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

    it 'should work when still expedited at end of data' do
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
end
