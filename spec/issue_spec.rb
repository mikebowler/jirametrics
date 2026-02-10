# frozen_string_literal: true

require './spec/spec_helper'

describe Issue do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:target_path) { 'spec/testdata/' }
  let(:project_config) do
    ProjectConfig.new exporter: exporter, target_path: target_path, jira_config: nil, block: nil
  end
  let(:board) do
    board = sample_board
    board.project_config = project_config
    statuses = board.possible_statuses
    statuses.clear
    statuses << Status.new(
      name: 'Backlog', id: 1, category_name: 'ready', category_id: 2, category_key: 'new'
    )
    statuses << Status.new(
      name: 'Selected for Development', id: 3, category_name: 'ready', category_id: 4, category_key: 'new'
    )
    statuses << Status.new(
      name: 'In Progress', id: 5, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Review', id: 7, category_name: 'in-flight', category_id: 8, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Done', id: 9, category_name: 'finished', category_id: 10, category_key: 'indeterminate'
    )

    statuses << Status.new(
      name: 'Blocked', id: 10, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Stalled', id: 11, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Doing', id: 12, category_name: 'finished', category_id: 10, category_key: 'done'
    )
    statuses << Status.new(
      name: 'Doing2', id: 13, category_name: 'finished', category_id: 10, category_key: 'done'
    )
    statuses << Status.new(
      name: 'Stalled2', id: 14, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Blocked2', id: 15, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    board
  end
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:issue2) { load_issue 'SP-2', board: board }

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
          'id' => '999',
          'statusCategory' => {
            'name' => 'To Do',
            'id' => 100,
            'key' => 'new'
          }
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
      expect { described_class.new raw: raw, board: nil }.to raise_error(
        'Unable to initialize SP-1'
      )
    end

    it 'raises wrapped error if no board passed in' do
      described_class.new raw: { 'key' => 'ABC-1' }, board: nil
      raise 'Should have failed because no board specified'
    rescue StandardError => e
      expect(e.message).to eq 'Unable to initialize ABC-1'
      expect(e.cause.message).to eq 'No board for issue ABC-1'
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
            'id' => '999',
            'statusCategory' => {
              'name' => 'To Do',
              'id' => 100,
              'key' => 'new'
            }
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

    it 'continues even when changelog has no history' do
      raw = {
        'key' => 'SP-1',
        'changelog' => {},
        'fields' => {
          'created' => '2021-08-29T18:00:00+00:00',
          'updated' => '2021-09-29T18:00:00+00:00',
          'status' => {
            'name' => 'BrandNew!',
            'id' => '999',
            'statusCategory' => {
              'name' => 'To Do',
              'id' => 100,
              'key' => 'new'
            }

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
        mock_change(
          issue: issue2, field: 'status', value: 'Backlog', value_id: 1, time: '2021-06-18T18:41:37.804'
        ),
        mock_change(
          issue: issue2, field: 'priority', value: 'Medium', time: '2021-06-18T18:41:37.804'
        ),
        mock_change(
          issue: issue2, field: 'status', value: 'Selected for Development', value_id: 3,
          time: '2021-06-18T18:43:38'
        )
      ]
    end

    it 'gets complex history with a mix of field types' do
      issue10 = load_issue('SP-10', board: board)
      expect(issue10.changes).to eq [
        mock_change(issue: issue10, field: 'status', value: 'Backlog', value_id: 1, time: '2021-06-18T18:42:52.754'),
        mock_change(issue: issue10, field: 'priority', value: 'Medium', time: '2021-06-18T18:42:52.754'),
        mock_change(
          issue: issue10, field: 'status', value: 'Selected for Development', value_id: 3, time: '2021-08-29T18:06:28'
        ),
        mock_change(issue: issue10, field: 'Rank', value: 'Ranked higher', time: '2021-08-29T18:06:28'),
        mock_change(issue: issue10, field: 'priority', value: 'Highest', time: '2021-08-29T18:06:43'),
        mock_change(issue: issue10, field: 'status', value: 'In Progress', value_id: 5, time: '2021-08-29T18:06:55'),
        mock_change(
          issue: issue10, field: 'status', value: 'Selected for Development', value_id: 3,
          time: '2021-09-06T04:33:11'
        ),
        mock_change(issue: issue10, field: 'Flagged', value: 'Impediment', time: '2021-09-06T04:33:30'),
        mock_change(issue: issue10, field: 'priority', value: 'Medium', time: '2021-09-06T04:33:50'),
        mock_change(issue: issue10, field: 'Flagged', value: '', time: '2021-09-06T04:33:55'),
        mock_change(issue: issue10, field: 'status', value: 'In Progress', value_id: 5, time: '2021-09-06T04:34:02'),
        mock_change(issue: issue10, field: 'status', value: 'Review', value_id: 7, time: '2021-09-06T04:34:21'),
        mock_change(issue: issue10, field: 'status', value: 'Done', value_id: 9, time: '2021-09-06T04:34:26'),
        mock_change(issue: issue10, field: 'resolution', value: 'Done', value_id: 9, time: '2021-09-06T04:34:26')
       ]
    end

    it "defaults the first status if there really hasn't been any yet" do
      issue = empty_issue created: '2021-08-29T18:00:00+00:00'
      expect(issue.changes).to eq [
        mock_change(
          issue: issue, field: 'status', value: 'Backlog', value_id: 10_000, time: '2021-08-29T18:00:00+00:00'
        )
      ]
    end
  end

  context 'first_time_in_status' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }

    it 'first time in status' do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-02')
      expect(issue.first_time_in_status('In Progress').time).to eql to_time('2021-10-02')
    end

    it "first time in status that doesn't match any" do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-02')
      expect(issue.first_time_in_status('NoStatus')).to be_nil
    end
  end

  context 'first_time_not_in_status' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }

    it 'first time not in status' do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-02')
      expect(issue.first_time_not_in_status('Backlog').time).to eql to_time('2021-10-02')
    end

    it "first time not in status where it's never in that status" do
      raw = {
        'key' => 'SP-1',
        'changelog' => { 'histories' => [] },
        'fields' => {
          'created' => '2021-08-29T18:00:00+00:00',
          'status' => {
            'name' => 'BrandNew!',
            'id' => '999',
            'statusCategory' => {
              'name' => 'To Do',
              'id' => 100,
              'key' => 'new'
            }
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
    let(:issue) { empty_issue created: '2021-06-01', board: board }

    it 'fails for invalid column name' do
      expect { issue.first_time_in_or_right_of_column 'NoSuchColumn' }.to raise_error(
        'No visible column with name: "NoSuchColumn" Possible options are: "Ready", "In Progress", "Review", "Done"'
      )
    end

    it 'works for happy path' do
      # The second column is called "In Progress" and it's only mapped to status 3
      add_mock_change(issue: issue, field: 'status', value: 'Backlog', value_id: 1, time: '2021-06-18')
      add_mock_change(issue: issue, field: 'status', value: 'Selected for Development', value_id: 3, time: '2021-07-18')

      expect(issue.first_time_in_or_right_of_column('In Progress').time).to eq to_time('2021-07-18')
    end

    it 'returns nil when no matches' do
      # The second column is called "In Progress" and it's only mapped to status 3
      add_mock_change(issue: issue, field: 'status', value: 'Backlog', value_id: 1, time: '2021-06-18')

      expect(issue.first_time_in_or_right_of_column 'In Progress').to be_nil
    end
  end

  context 'still_in_or_right_of_column' do
    let(:issue) { empty_issue created: '2021-06-01', board: board }

    it 'works for happy path' do
      # The second column is called "In Progress" and it's only mapped to status 3
      add_mock_change(issue: issue, field: 'status', value: 'Backlog', value_id: 1, time: '2021-06-01')
      add_mock_change(issue: issue, field: 'status', value: 'Selected for Development', value_id: 3, time: '2021-06-02')
      add_mock_change(issue: issue, field: 'status', value: 'Backlog', value_id: 1, time: '2021-06-03')
      add_mock_change(issue: issue, field: 'status', value: 'Selected for Development', value_id: 3, time: '2021-06-04')
      add_mock_change(issue: issue, field: 'status', value: 'Selected for Development', value_id: 3, time: '2021-06-05')

      expect(issue.still_in_or_right_of_column('In Progress').time).to eq to_time('2021-06-04')
    end
  end

  context 'first_time_in_status_category' do
    let(:issue) { empty_issue created: '2021-06-01', board: board }

    it 'matches first time in status category' do
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-06-02')
      expect(issue.first_time_in_status_category('finished').time).to eq to_time('2021-06-02')
    end

    it 'never matches' do
      expect(issue.first_time_in_status_category('finished')).to be_nil
    end
  end

  context 'first_status_change_after_created' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }

    it "finds first time for any status change - created doesn't count as status change" do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-02')
      expect(issue.first_status_change_after_created.time).to eq to_time('2021-10-02')
    end

    it %(first status change after created, where there isn't anything after created) do
      raw = {
        'key' => 'SP-1',
        'changelog' => { 'histories' => [] },
        'fields' => {
          'created' => '2021-08-29T18:00:00+00:00',
          'status' => {
            'name' => 'BrandNew!',
            'id' => '999',
            'statusCategory' => {
              'name' => 'To Do',
              'id' => 100,
              'key' => 'new'
            }
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
    let(:issue) { empty_issue created: '2021-10-01', board: board }

    it 'item moved to done and then back to in progress' do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-01')
      expect(issue.currently_in_status('Done')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-04')
      expect(issue.currently_in_status('Done').time).to eql to_time('2021-10-04')
    end

    it 'has no status changes' do
      issue.changes.clear
      expect(issue.currently_in_status('Done')).to be_nil
    end
  end

  context 'still_in_status' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }

    it 'item moved to done and then back to in progress' do
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-03')
      expect(issue.still_in_status('Done')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-04')
      expect(issue.still_in_status('Done').time).to eql to_time('2021-10-04')
    end

    it 'item moved to done twice should return first time only' do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-04')
      expect(issue.still_in_status('Done').time).to eql to_time('2021-10-03')
    end

    it "doesn't match any" do
      expect(issue.still_in_status('NoStatus')).to be_nil
    end
  end

  context 'currently_in_status_category' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }

    it 'item moved to done and then back to in progress' do
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-03')
      expect(issue.currently_in_status_category('finished')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-04')
      expect(issue.currently_in_status_category('finished').time).to eql to_time('2021-10-04')
    end

    it 'has no status changes' do
      issue.changes.clear
      expect(issue.currently_in_status_category('finished')).to be_nil
    end
  end

  context 'still_in_status_category' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }

    it 'item moved to done and then back to in progress' do
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-03')
      expect(issue.still_in_status_category('finished')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-05')
      expect(issue.still_in_status_category('finished').time).to eql to_time('2021-10-05')
    end

    it 'item moved to done twice should return first time only' do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-01')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 9, time: '2021-10-03')
      expect(issue.still_in_status_category('finished').time).to eql to_time('2021-10-02')
    end
  end

  context 'first_time_label_added' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }

    it 'does not match when no labels' do
      expect(issue.first_time_label_added('refined')).to be_nil
    end

    it 'does not match when wrong labels' do
      add_mock_change(issue: issue, field: 'labels', value: 'xxx', time: '2021-10-01')
      expect(issue.first_time_label_added('refined')).to be_nil
    end

    it 'matches for issue with one label' do
      add_mock_change(issue: issue, field: 'labels', value: 'refined', time: '2021-10-01')
      expect(issue.first_time_label_added('refined').time).to eql to_time('2021-10-01')
    end

    it 'matches for issue with two labels' do
      add_mock_change(issue: issue, field: 'labels', value: 'xxx refined', time: '2021-10-01')
      expect(issue.first_time_label_added('refined').time).to eql to_time('2021-10-01')
    end

    it 'matches second label for issue with two labels' do
      add_mock_change(issue: issue, field: 'labels', value: 'xxx refined', time: '2021-10-01')
      expect(issue.first_time_label_added('yyy', 'xxx').time).to eql to_time('2021-10-01')
    end
  end

  context 'first_time_visible_on_board' do
    let(:issue) { empty_issue created: '2021-10-01', board: sample_board }

    it 'does not match when not visible' do
      expect(issue.first_time_visible_on_board).to be_nil
    end

    it 'does not match when wrong labels' do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 3, time: '2021-10-03')
      expect(issue.first_time_visible_on_board&.time).to eq to_time('2021-10-03')
    end
  end

  context 'first_time_added_to_active_sprint' do
    let(:scrum_board) { board.tap { |b| b.raw['type'] = 'scrum' } }
    let(:issue) { empty_issue created: '2021-10-01', board: scrum_board }

    it 'raises error when used on kanban board' do
      issue = empty_issue created: '2021-10-01', board: board
      expect { issue.first_time_added_to_active_sprint }.to raise_error(
        'first_time_added_to_active_sprint() can only be used with Scrum boards: ' \
        'issue=SP-1, board=Board(id: 1, name: "SP board", board_type: "kanban")'
      )
    end

    it 'matches if the sprint had already started on add' do
      issue.board.sprints << Sprint.new(raw: {
        'id' => 10,
        'state' => 'active',
        'name' => 'Scrum Sprint 1',
        'startDate' => '2021-10-04T00:00:00.000Z',
        'endDate' => '22021-10-23T00:00:00.000Z',
        'completeDate' => '2021-10-23T00:00:00.000Z',
        'originBoardId' => 2
      }, timezone_offset: '+00:00')

      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '10', time: '2021-10-03',
        field_id: 'customfield_10020'
      )
      expect(issue.first_time_added_to_active_sprint&.time).to eq to_time('2021-10-03')
    end

    it 'does not match if the sprint never starts' do
      issue.board.sprints << Sprint.new(raw: {
        'id' => 10,
        'state' => 'pending',
        'name' => 'Scrum Sprint 1',
        'originBoardId' => 2
      }, timezone_offset: '+00:00')

      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '10', time: '2021-10-03',
        field_id: 'customfield_10020'
      )
      expect(issue.first_time_added_to_active_sprint&.time).to be_nil
    end

    it 'does not match if it was removed from the sprint before the sprint started' do
      issue.board.sprints << Sprint.new(raw: {
        'id' => 10,
        'state' => 'active',
        'name' => 'Scrum Sprint 1',
        'startDate' => '2021-10-04T00:00:00.000Z',
        'originBoardId' => 2
      }, timezone_offset: '+00:00')

      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '10',
        time: '2021-10-03', field_id: 'customfield_10020'
      )
      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '', old_value_id: '10',
        time: '2021-10-04', field_id: 'customfield_10020'
      )
      expect(issue.first_time_added_to_active_sprint&.time).to be_nil
    end

    it 'does not match if it was removed from the sprint and the sprint never started anyway' do
      issue.board.sprints << Sprint.new(raw: {
        'id' => 10,
        'state' => 'active',
        'name' => 'Scrum Sprint 1',
        'originBoardId' => 2
      }, timezone_offset: '+00:00')
      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '10',
        time: '2021-10-03', field_id: 'customfield_10020'
      )
      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '', old_value_id: '10',
        time: '2021-10-04', field_id: 'customfield_10020'
      )
      expect(issue.first_time_added_to_active_sprint&.time).to be_nil
    end

    it 'matches if it was removed after sprint start' do
      issue.board.sprints << Sprint.new(raw: {
        'id' => 10,
        'state' => 'active',
        'name' => 'Scrum Sprint 1',
        'startDate' => '2021-10-04T00:00:00.000Z',
        'originBoardId' => 2
      }, timezone_offset: '+00:00')

      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '10',
        time: '2021-10-03', field_id: 'customfield_10020'
      )
      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '', old_value_id: '10',
        time: '2021-10-05', field_id: 'customfield_10020'
      )
      expect(issue.first_time_added_to_active_sprint&.time).to eq to_time('2021-10-03')
    end

    it 'matches when the sprint data is not in the list of sprints' do
      issue.raw['fields']['customfield_10020'] = [
        {
          'id' => 10,
          'name' => 'Sprint 1',
          'state' => 'closed',
          'boardId' => 2,
          'goal' => '',
          'startDate' => '2021-10-04T00:00:00.000Z',
          'endDate' => '2021-10-23T00:00:00.000Z',
          'completeDate' => '2021-10-23T00:00:00.000Z'
        }
     ]
      add_mock_change(
        issue: issue, field: 'Sprint', value: 'Sprint 1', value_id: '10', time: '2021-10-03',
        field_id: 'customfield_10020'
      )
      expect(issue.first_time_added_to_active_sprint&.time).to eq to_time('2021-10-03')
    end
  end

  context 'blocked_stalled_changes' do
    let(:issue) { empty_issue created: '2021-10-01', board: board }
    let(:settings) do
      {
        'blocked_statuses' => %w[Blocked Blocked2],
        'stalled_statuses' => %w[Stalled Stalled2],
        'blocked_link_text' => ['is blocked by'],
        'stalled_threshold_days' => 5,
        'flagged_means_blocked' => true
      }
    end

    it 'handles never blocked' do
      issue = empty_issue created: '2021-10-01', board: board
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-05')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(time: to_time('2021-10-05'))
      ]
    end

    it 'handles flagged and unflagged' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
      add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-05')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(flagged: 'Blocked', time: to_time('2021-10-03T00:01:00')),
        BlockedStalledChange.new(time: to_time('2021-10-03T00:02:00')),
        BlockedStalledChange.new(time: to_time('2021-10-05'))
      ]
    end

    it 'ignores flagged when "flagged_means_blocked" is false' do
      settings['flagged_means_blocked'] = false
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
      add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-05')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(time: to_time('2021-10-05'))
      ]
    end

    it 'handles contiguous blocked status' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status', value: 'Blocked2', value_id: 15, time: '2021-10-04')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-05')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-06')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(status: 'Blocked', time: to_time('2021-10-03')),
        BlockedStalledChange.new(status: 'Blocked2', time: to_time('2021-10-04')),
        BlockedStalledChange.new(time: to_time('2021-10-05')),
        BlockedStalledChange.new(time: to_time('2021-10-06'))
      ]
    end

    it 'handles blocked statuses' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status',  value: 'Blocked', value_id: 10, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-04')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-06')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(status: 'Blocked', time: to_time('2021-10-03')),
        BlockedStalledChange.new(time: to_time('2021-10-04')),
        BlockedStalledChange.new(time: to_time('2021-10-06'))
      ]
    end

    it 'handles blocked on issues' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(
        issue: issue, field: 'Link', value: 'This issue is blocked by SP-10', time: '2021-10-02'
      )
      add_mock_change(
        issue: issue, field: 'Link', value: nil, old_value: 'This issue is blocked by SP-10', time: '2021-10-03'
      )
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-04')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(blocking_issue_keys: ['SP-10'], time: to_time('2021-10-02')),
        BlockedStalledChange.new(time: to_time('2021-10-03')),
        BlockedStalledChange.new(time: to_time('2021-10-04'))
      ]
    end

    it 'handles stalled for inactivity' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Doing', value_id: 12, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'Doing2', value_id: 13, time: '2021-10-08')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-10')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(stalled_days: 6, time: to_time('2021-10-02T01:00:00')),
        BlockedStalledChange.new(time: to_time('2021-10-08')),
        BlockedStalledChange.new(time: to_time('2021-10-10'))
      ]
    end

    it 'handles contiguous stalled status' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status',  value: 'Stalled', value_id: 11, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status',  value: 'Stalled2', value_id: 14, time: '2021-10-04')
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-05')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-06')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(status: 'Stalled', status_is_blocking: false, time: to_time('2021-10-03')),
        BlockedStalledChange.new(status: 'Stalled2', status_is_blocking: false, time: to_time('2021-10-04')),
        BlockedStalledChange.new(time: to_time('2021-10-05')),
        BlockedStalledChange.new(time: to_time('2021-10-06'))
      ]
    end

    it 'handles stalled statuses' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status',  value: 'Stalled', value_id: 11, time: '2021-10-03')
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-04')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-06')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(status: 'Stalled', status_is_blocking: false, time: to_time('2021-10-03')),
        BlockedStalledChange.new(time: to_time('2021-10-04')),
        BlockedStalledChange.new(time: to_time('2021-10-06'))
      ]
    end

    it 'does not report stalled if subtasks were active through the period' do
      # The main issue has activity on the 2nd and again on the 8th. If we don't take subtasks
      # into account then we'd expect it to show stalled between those dates. Given that we
      # should consider subtasks, it should show nothing stalled through the period.

      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Doing', value_id: 12, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'Doing2', value_id: 13, time: '2021-10-08')

      subtask = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: subtask, field: 'status', value: 'Doing', value_id: 12, time: '2021-10-05')
      issue.subtasks << subtask

      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-10')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(time: to_time('2021-10-10'))
      ]
    end

    it 'splits stalled into sections if subtasks were active in between' do
      # The full range is 1st to 12th with subtask activity on the 5th. The only
      # stalled section in here is 5-12.
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Doing', value_id: 12, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'Doing2', value_id: 13, time: '2021-10-12')

      subtask = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: subtask, field: 'status', value: 'Doing', value_id: 12, time: '2021-10-05')
      issue.subtasks << subtask

      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-13')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(stalled_days: 7, time: to_time('2021-10-05T01:00:00')),
        BlockedStalledChange.new(time: to_time('2021-10-12')),
        BlockedStalledChange.new(time: to_time('2021-10-13'))
      ]
    end

    it 'ignores the final artificial change for the purposes of stalled' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Doing', value_id: 12, time: '2021-10-02')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-08')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
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

    it 'shows blocked even when there has been a big enough gap to be stalled' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-10')
      expect(issue.blocked_stalled_changes settings: settings, end_time: to_time('2021-10-10')).to eq [
        BlockedStalledChange.new(time: to_time('2021-10-01')),
        BlockedStalledChange.new(status: 'Blocked', time: to_time('2021-10-02')),
        BlockedStalledChange.new(time: to_time('2021-10-10')),
        BlockedStalledChange.new(time: to_time('2021-10-10'))
      ]
    end
  end

  context 'blocked_stalled_by_date' do
    it 'handles no changes' do
      issue = empty_issue created: '2021-10-01', board: board
      actual = issue.blocked_stalled_by_date(
        date_range: to_date('2021-10-02')..to_date('2021-10-04'),
        chart_end_time: to_time('2021-10-04T23:59:59')
      )
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-10-02') => :active,
        to_date('2021-10-03') => :active,
        to_date('2021-10-04') => :active
      })
    end

    it 'tracks blocked over multiple days' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')

      actual = issue.blocked_stalled_by_date(
        date_range: to_date('2021-10-02')..to_date('2021-10-04'),
        chart_end_time: to_time('2021-10-04T23:59:59')
      )
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-10-02') => :active,
        to_date('2021-10-03') => :blocked,
        to_date('2021-10-04') => :blocked
      })
    end

    it 'tracks blocked then unblocked' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
      add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
      add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')

      actual = issue.blocked_stalled_by_date(
        date_range: to_date('2021-10-02')..to_date('2021-10-04'),
        chart_end_time: to_time('2021-10-04T23:59:59')
      )
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-10-02') => :active,
        to_date('2021-10-03') => :blocked,
        to_date('2021-10-04') => :active
      })
    end

    it 'handles a date range that covers time before the issue starts and after it finishes' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked', time: '2021-10-02')

      actual = issue.blocked_stalled_by_date(
        date_range: to_date('2021-09-30')..to_date('2021-10-03'),
        chart_end_time: to_time('2021-10-04T23:59:59')
      )
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-09-30') => :active,
        to_date('2021-10-01') => :active,
        to_date('2021-10-02') => :blocked,
        to_date('2021-10-03') => :blocked
      })
    end

    it 'handles complex case' do
      issue = empty_issue created: '2021-10-01', board: board
      add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-07T00:01:00')
      add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-07T00:02:00')

      add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-09')
      add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-11')

      actual = issue.blocked_stalled_by_date(
        date_range: to_date('2021-10-01')..to_date('2021-10-12'),
        chart_end_time: to_time('2021-10-12T23:59:59')
      )
      expect(actual.transform_values(&:as_symbol)).to eq({
        to_date('2021-10-01') => :active,  # created and therefore active
        to_date('2021-10-02') => :stalled, # no activity for the next five days so start tracking stalled
        to_date('2021-10-03') => :stalled, # no change
        to_date('2021-10-04') => :stalled, # no change
        to_date('2021-10-05') => :stalled, # no change
        to_date('2021-10-06') => :stalled, # no change
        to_date('2021-10-07') => :blocked, # blocked and unblocked same day
        to_date('2021-10-08') => :active,
        to_date('2021-10-09') => :blocked, # becomes blocked
        to_date('2021-10-10') => :blocked, # No changes on this day, should still be blocked
        to_date('2021-10-11') => :active, # block cleared
        to_date('2021-10-12') => :active
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
      issue = empty_issue created: '2021-10-01T00:00:00+00:00', board: board
      add_mock_change(
        issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-02T00:00:00+00:00'
      )
      add_mock_change(
        issue: issue, field: 'resolution', value: 'Done', time: '2021-10-03T01:00:00+00:00'
      )
      add_mock_change(
        issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-04T02:00:00+00:00'
      )
      add_mock_change(
        issue: issue, field: 'resolution', value: 'Done', time: '2021-10-05T01:00:00+00:00'
      )
      add_mock_change(
        issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-06T02:00:00+00:00'
      )
      add_mock_change(issue: issue, field: 'resolution', value: 'Done', time: '2021-10-07T01:00:00+00:00')

      expect([issue.first_resolution.time, issue.last_resolution.time]).to eq [
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
        Status.new(
          name: 'In Progress', id: 3, category_name: 'In Progress', category_id: 4, category_key: 'indeterminate'
        )
      )
    end
  end

  context 'last_activity' do
    let(:issue) { empty_issue created: '2020-01-01', board: board }

    it 'handles no activity, ever' do
      expect(issue.last_activity now: to_time('2001-01-01')).to be_nil
    end

    it 'picks most recent change' do
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2020-01-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2020-01-03')
      expect(issue.last_activity now: to_time('2021-01-01')).to eq to_time('2020-01-03')
    end

    it 'handles subtask with no changes' do
      subtask = empty_issue created: '2020-01-02', board: board
      issue.subtasks << subtask
      expect(issue.last_activity now: to_time('2021-02-01')).to eq to_time('2020-01-02')
    end

    it 'handles multiple subtasks, each with changes' do
      subtask1 = empty_issue created: '2020-01-02', board: board
      add_mock_change(issue: subtask1, field: 'status', value: 'In Progress', value_id: 5, time: '2020-01-03')
      issue.subtasks << subtask1

      subtask2 = empty_issue created: '2020-01-02', board: board
      add_mock_change(issue: subtask2, field: 'status', value: 'In Progress', value_id: 5, time: '2020-01-04')
      issue.subtasks << subtask2

      expect(issue.last_activity now: to_time('2021-01-01')).to eq to_time('2020-01-04')
    end

    it 'handles no activity on the subtask but activity on the main issue' do
      subtask = empty_issue created: '2020-01-01', board: board
      issue.subtasks << subtask

      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2020-01-02')

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

      it 'warns when parent link points to something that is not a parent id' do
        project_config.settings['customfield_parent_links'] = 'customfield_1'
        issue.board.project_config = project_config
        issue.raw['fields']['customfield_1'] = 'BadData'
        expect(issue.parent_key).to be_nil
        expect(exporter.file_system.log_messages).to eq([
          'Custom field "customfield_1" should point to a parent id but found "BadData"'
        ])
      end
    end
  end

  context 'looks_like_issue_key?' do
    let(:issue) { empty_issue created: '2020-01-01' }

    it 'returns true for valid key' do
      expect(issue.looks_like_issue_key? 'ABC-123').to be true
    end

    it 'returns false for invalid key' do
      expect(issue.looks_like_issue_key? 'BadData').to be false
    end

    it 'returns false for value that is not a string' do
      expect(issue.looks_like_issue_key?({ a: 1 })).to be false
    end
  end

  context 'expedited?' do
    let(:issue) { empty_issue created: '2020-01-01', board: board }

    it 'no priority set' do
      expect(issue).not_to be_expedited
    end

    it 'priority set but not expedited' do
      issue.raw['fields']['priority'] = 'high'
      expect(issue).not_to be_expedited
    end

    it 'priority set to expedited' do
      issue.raw['fields']['priority'] = { 'name' => 'high' }
      issue.board.project_config.settings['expedited_priority_names'] = ['high']
      expect(issue).to be_expedited
    end
  end

  context 'expedited_on_date?' do
    it 'works when expedited turns on and off on same day' do
      issue = empty_issue created: '2021-10-01', board: board
      issue.board.project_config.settings['expedited_priority_names'] = ['high']

      add_mock_change(issue: issue, field: 'priority', value: 'high', time: '2021-10-03T00:01:00')
      add_mock_change(issue: issue, field: 'priority', value: '',     time: '2021-10-03T00:02:00')

      actual = [
        issue.expedited_on_date?(to_date('2021-10-02')),
        issue.expedited_on_date?(to_date('2021-10-03')),
        issue.expedited_on_date?(to_date('2021-10-04'))
      ]
      expect(actual).to eq [false, true, false]
    end

    it 'works when one expedite follows another' do
      issue = empty_issue created: '2021-10-01', board: board
      issue.board.project_config.settings['expedited_priority_names'] = %w[high higher]

      add_mock_change(issue: issue, field: 'priority', value: 'high', time: '2021-10-02T00:01:00')
      add_mock_change(issue: issue, field: 'priority', value: 'higher', time: '2021-10-03T00:02:00')
      add_mock_change(issue: issue, field: 'priority', value: '', time: '2021-10-03T00:04:00')

      actual = [
        issue.expedited_on_date?(to_date('2021-10-01')),
        issue.expedited_on_date?(to_date('2021-10-02')),
        issue.expedited_on_date?(to_date('2021-10-03')),
        issue.expedited_on_date?(to_date('2021-10-04'))
      ]
      expect(actual).to eq [false, true, true, false]
    end

    it 'works when still expedited at end of data' do
      issue = empty_issue created: '2021-10-01', board: board
      issue.board.project_config.settings['expedited_priority_names'] = %w[high higher]

      add_mock_change(issue: issue, field: 'priority', value: 'high', time: '2021-10-02T00:01:00')

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
      issue1.board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil]
      ]

      expect(issue1.dump).to eq <<~TEXT
        SP-1 (Story): Create new draft event
          History:
            2021-06-18 18:41:29 +0000 [priority] "Medium" (Artificial entry)
            2021-06-18 18:41:29 +0000 [  status] "Backlog":10000 (Artificial entry)
            2021-06-18 18:43:34 +0000 [  status] "Backlog":10000 -> "Selected for Development":10001 (Author: Mike Bowler)
            2021-06-18 18:44:21 +0000 [  status] "Selected for Development":10001 -> "In Progress":3 (Author: Mike Bowler)
            2021-08-29 18:04:39 +0000 [ Flagged] "Impediment" (Author: Mike Bowler)
      TEXT
    end

    it 'dumps complex issue' do
      issue1.board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2021-06-18T18:44:21', nil]
      ]
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
          History:
            2021-06-18 18:41:29 +0000 [priority] "Medium" (Artificial entry)
            2021-06-18 18:41:29 +0000 [  status] "Backlog":10000 (Artificial entry)
            2021-06-18 18:43:34 +0000 [  status] "Backlog":10000 -> "Selected for Development":10001 (Author: Mike Bowler)
            2021-06-18 18:44:21 +0000 [--------] ↓↓↓↓ Started here ↓↓↓↓
            2021-06-18 18:44:21 +0000 [  status] "Selected for Development":10001 -> "In Progress":3 (Author: Mike Bowler)
            2021-08-29 18:04:39 +0000 [ Flagged] "Impediment" (Author: Mike Bowler)
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

  context 'flow_efficiency_numbers' do # part of a flow efficiency calculation
    let(:settings) do
      {
        'blocked_statuses' => %w[Blocked Blocked2],
        'stalled_statuses' => %w[Stalled Stalled2],
        'stalled_threshold_days' => 5
      }
    end
    let(:seconds_per_day) { (60 * 60 * 24).to_f }

    it 'returns zeros when issue never started' do
      issue = empty_issue created: '2000-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, nil, nil]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-02'), settings: settings))
        .to eq [0, 0]
    end

    it 'is created in active status and never changed' do
      issue = empty_issue created: '2000-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, issue.created, nil]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-02'), settings: settings))
        .to eq [seconds_per_day, seconds_per_day]
    end

    it 'becomes blocked before issue starts and stays that way' do
      issue = empty_issue created: '2000-01-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-01T00:01:00')
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, to_time('2000-01-02'), nil]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-03'), settings: settings))
        .to eq [seconds_per_day, seconds_per_day]
    end

    it 'becomes blocked but issue does not start before end_time' do
      issue = empty_issue created: '2000-01-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-01T00:01:00')
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, to_time('2000-01-04'), nil]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-03'), settings: settings))
        .to eq [0.0, 0.0]
    end

    it 'becomes blocked after done' do
      issue = empty_issue created: '2000-01-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-03')
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, to_time('2000-01-01'), to_time('2000-01-02')]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-04'), settings: settings))
        .to eq [seconds_per_day, seconds_per_day]
    end

    it 'becomes blocked and then unblocked before start' do
      issue = empty_issue created: '2000-01-01', board: board
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2000-01-03')
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, to_time('2000-01-04'), nil]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-05'), settings: settings))
        .to eq [seconds_per_day, seconds_per_day]
    end

    it 'was created in blocked status' do
      issue = empty_issue created: '2000-01-01', board: board, creation_status: ['Blocked', 1]
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, to_time('2000-01-01'), nil]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-02'), settings: settings))
        .to eq [0.0, seconds_per_day]
    end

    it 'was created in done status' do
      issue = empty_issue created: '2000-01-01', board: board, creation_status: ['Done', 1]
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, to_time('2000-01-01'), to_time('2000-01-01')]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-02'), settings: settings))
        .to eq [0.0, 0.0]
    end

    it 'handles complex case with multiple block/unblock' do
      issue = empty_issue created: '2000-01-01', board: board
      # active for a day here
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-02')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2000-01-03')
      # active for a day here
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-04')
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-05') # 2nd blocked
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2000-01-06')
      # active for a day here, then issue finishes. The last two blocked should be ignored
      add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2000-01-09')
      add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2000-01-10')

      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, to_time('2000-01-01'), to_time('2000-01-08')]
      ]
      expect(issue.flow_efficiency_numbers(end_time: to_time('2000-01-07'), settings: settings))
        .to eq [seconds_per_day * 3, seconds_per_day * 6]
    end
  end

  context 'find_or_create_status' do
    it 'returns status when present' do
      expect(issue1.find_or_create_status id: 1, name: 'foo').to eq(
        Status.new name: 'Backlog', id: 1, category_name: 'ready', category_id: 2, category_key: 'new'
      )
    end

    it 'creates status' do
      expect(issue1.find_or_create_status id: 1000, name: 'foo').to eq(
        Status.new name: 'foo', id: 1000, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
      )
      expect(exporter.file_system.log_messages).to eq([
        [
          'Warning: The history for issue SP-1 references the status ("foo":1000) that can\'t be found. We are ' \
            'guessing that this belongs to the "in-flight":6 status category but that may be wrong. See ' \
            'https://jirametrics.org/faq/#q1 for more details on defining statuses.',
          'The statuses we did find are: ' \
            '["Backlog":1, "Blocked":10, "Blocked2":15, "Doing":12, "Doing2":13, "Done":9, "In Progress":5, ' \
            '"Review":7, "Selected for Development":3, "Stalled":11, "Stalled2":14]'
        ]
      ])
    end

    it 'raises error if no in-progress statuses can be found' do
      issue1.board.possible_statuses.clear
      expect { issue1.find_or_create_status id: 1, name: 'foo' }.to raise_error(
        "Can't find even one in-progress status in []"
      )
    end
  end

  context 'due_date' do
    it 'handles none' do
      expect(issue1.due_date).to be_nil
    end

    it 'parses correctly' do
      issue1.raw['fields']['duedate'] = '2024-01-01'
      expect(issue1.due_date).to eq Date.parse('2024-01-01')
    end
  end

  context '<=>' do
    it 'compares numerically when projects are the same' do
      issue1 = empty_issue created: '2024-01-01', key: 'SP-1'
      issue2 = empty_issue created: '2024-01-01', key: 'SP-2'

      expect(issue1 <=> issue2).to be_negative
    end

    it 'compares alphametically by project name when projects are different' do
      issue1 = empty_issue created: '2024-01-01', key: 'SP-1'
      issue2 = empty_issue created: '2024-01-01', key: 'ABC-2'

      expect(issue1 <=> issue2).to be_positive
    end

    it 'compares equal' do
      issue1 = empty_issue created: '2024-01-01', key: 'SP-1'
      issue2 = empty_issue created: '2024-01-01', key: 'SP-1'

      expect(issue1 <=> issue2).to be_zero
    end
  end

  context 'compact_text' do
    it 'returns empty for nil' do
      expect(issue1.compact_text nil).to eq ''
    end

    it 'truncates when too long' do
      expect(issue1.compact_text '123456789', max: 3).to eq '123...'
    end

    it 'passes through when within limit' do
      expect(issue1.compact_text '123456789', max: 30).to eq '123456789'
    end

    it 'expands ADF without compressing' do
      input = {
        'type' => 'doc',
        'version' => 1,
        'content' => [
          {
            'type' => 'paragraph',
            'content' => [
              {
                'type' => 'text',
                'text' => 'Comment 2'
              }
            ]
          }
        ]
      }
      expect(issue1.compact_text input, max: 30).to eq '<p>Comment 2</p>'
    end
  end

  context 'parse_time' do
    it 'parses string' do
      expect(issue1.parse_time('2021-01-13T14:13:42.257-0500').to_s).to eq(
        '2021-01-13 19:13:42 +0000'
      )
    end

    it 'parses int' do
      expect(issue1.parse_time(1_759_080_993_142).to_s).to eq(
        '2025-09-28 17:36:33 +0000'
      )
    end
  end

  context 'assigned_to' do
    it 'is assigned' do
      issue1.raw['fields']['assignee'] = { 'displayName' => 'Fred' }
      expect(issue1.assigned_to).to eq 'Fred'
    end

    it 'is not assigned' do
      expect(issue1.assigned_to).to be_nil
    end
  end

  context 'assigned_to_icon_url' do
    it 'is assigned' do
      issue1.raw['fields']['assignee'] = { 'avatarUrls' => { '16x16' => 'myurl' } }
      expect(issue1.assigned_to_icon_url).to eq 'myurl'
    end

    it 'is not assigned' do
      expect(issue1.assigned_to_icon_url).to be_nil
    end
  end

  context 'time_created' do
    it 'returns the first item, which will be the created one' do
      expect(issue1.time_created.time).to eq issue1.created
    end
  end
end
