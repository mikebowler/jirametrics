# frozen_string_literal: true

require './spec/spec_helper'

describe BlockedStalledChangeStreamBuilder do
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
  let(:settings) do
    {
      'blocked_statuses' => status_collection_for(board: board, names: %w[Blocked Blocked2]),
      'stalled_statuses' => status_collection_for(board: board, names: %w[Stalled Stalled2]),
      'blocked_link_text' => ['is blocked by'],
      'stalled_threshold_days' => 5,
      'flagged_means_blocked' => true
    }
  end

  def stream issue, settings:, end_time:
    BlockedStalledChangeStreamBuilder.new(
      changes: issue.changes,
      settings: settings,
      created: issue.created,
      key: issue.key,
      subtask_activity_times: issue.all_subtask_activity_times,
      atlassian_document_format: issue.board.project_config.atlassian_document_format
    ).build(end_time: end_time)
  end

  it 'handles never blocked' do
    issue = empty_issue created: '2021-10-01', board: board
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-05'))).to eq [
      BlockedStalledChange.new(time: to_time('2021-10-01')),
      BlockedStalledChange.new(time: to_time('2021-10-05'))
    ]
  end

  it 'handles flagged and unflagged' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
    add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-05'))).to eq [
      BlockedStalledChange.new(time: to_time('2021-10-01')),
      BlockedStalledChange.new(flagged: 'Blocked', time: to_time('2021-10-03T00:01:00')),
      BlockedStalledChange.new(time: to_time('2021-10-03T00:02:00')),
      BlockedStalledChange.new(time: to_time('2021-10-05'))
    ]
  end

  it 'sets flag_reason from comment at the same timestamp as the flag' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked', time: '2021-10-03T00:01:00')
    add_mock_change(issue: issue, field: 'comment', value: 'Waiting on external team', time: '2021-10-03T00:01:00')
    add_mock_change(issue: issue, field: 'Flagged', value: '', time: '2021-10-03T00:02:00')
    # The comment change at the same timestamp generates a second blocked entry (comment iteration also
    # produces a BlockedStalledChange since flag is still set when the comment is processed in the loop)
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-05'))).to eq [
      BlockedStalledChange.new(time: to_time('2021-10-01')),
      BlockedStalledChange.new(
        flagged: 'Blocked', flag_reason: 'Waiting on external team', time: to_time('2021-10-03T00:01:00')
      ),
      BlockedStalledChange.new(
        flagged: 'Blocked', flag_reason: 'Waiting on external team', time: to_time('2021-10-03T00:01:00')
      ),
      BlockedStalledChange.new(time: to_time('2021-10-03T00:02:00')),
      BlockedStalledChange.new(time: to_time('2021-10-05'))
    ]
  end

  it 'sets flag_reason from comment within 30 seconds after the flag' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked', time: '2021-10-03T00:01:00')
    add_mock_change(issue: issue, field: 'comment', value: 'Waiting on vendor', time: '2021-10-03T00:01:15')
    add_mock_change(issue: issue, field: 'Flagged', value: '', time: '2021-10-03T00:02:00')
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-05'))).to eq [
      BlockedStalledChange.new(time: to_time('2021-10-01')),
      BlockedStalledChange.new(
        flagged: 'Blocked', flag_reason: 'Waiting on vendor', time: to_time('2021-10-03T00:01:00')
      ),
      BlockedStalledChange.new(
        flagged: 'Blocked', flag_reason: 'Waiting on vendor', time: to_time('2021-10-03T00:01:15')
      ),
      BlockedStalledChange.new(time: to_time('2021-10-03T00:02:00')),
      BlockedStalledChange.new(time: to_time('2021-10-05'))
    ]
  end

  it 'converts ADF comment body to html for flag_reason' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
    adf_body = {
      'type' => 'doc', 'version' => 1,
      'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Waiting on vendor' }] }]
    }
    add_mock_change(issue: issue, field: 'comment', value: adf_body, time: '2021-10-03T00:01:00')
    result = stream(issue, settings: settings, end_time: to_time('2021-10-05'))
    expect(result[1].flag_reason).to eq 'Waiting on vendor'
  end

  it 'strips the Jira-generated flag preamble leaving the real reason' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
    add_mock_change(
      issue: issue, field: 'comment', value: ":flag_on: Flag added\nWaiting on vendor", time: '2021-10-03T00:01:00'
    )
    result = stream(issue, settings: settings, end_time: to_time('2021-10-05'))
    expect(result[1].flag_reason).to eq 'Waiting on vendor'
  end

  it 'sets flag_reason to nil when comment is only the Jira-generated flag preamble' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
    add_mock_change(issue: issue, field: 'comment', value: ':flag_on: Flag added', time: '2021-10-03T00:01:00')
    result = stream(issue, settings: settings, end_time: to_time('2021-10-05'))
    expect(result[1].flag_reason).to be_nil
  end

  it 'leaves flag_reason nil when no comment matches the flag timestamp' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
    add_mock_change(issue: issue, field: 'comment', value: 'Unrelated comment', time: '2021-10-04T00:00:00')
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-05'))).to eq [
      BlockedStalledChange.new(time: to_time('2021-10-01')),
      BlockedStalledChange.new(flagged: 'Blocked', flag_reason: nil, time: to_time('2021-10-03T00:01:00')),
      BlockedStalledChange.new(flagged: 'Blocked', flag_reason: nil, time: to_time('2021-10-04T00:00:00')),
      BlockedStalledChange.new(flagged: 'Blocked', flag_reason: nil, time: to_time('2021-10-05'))
    ]
  end

  it 'ignores flagged when "flagged_means_blocked" is false' do
    settings['flagged_means_blocked'] = false
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status',  value: 'In Progress', value_id: 5, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'Flagged', value: 'Blocked',     time: '2021-10-03T00:01:00')
    add_mock_change(issue: issue, field: 'Flagged', value: '',            time: '2021-10-03T00:02:00')
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-05'))).to eq [
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
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-06'))).to eq [
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
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-06'))).to eq [
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
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-04'))).to eq [
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
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-10'))).to eq [
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
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-06'))).to eq [
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
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-06'))).to eq [
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

    expect(stream(issue, settings: settings, end_time: to_time('2021-10-10'))).to eq [
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

    expect(stream(issue, settings: settings, end_time: to_time('2021-10-13'))).to eq [
      BlockedStalledChange.new(time: to_time('2021-10-01')),
      BlockedStalledChange.new(stalled_days: 7, time: to_time('2021-10-05T01:00:00')),
      BlockedStalledChange.new(time: to_time('2021-10-12')),
      BlockedStalledChange.new(time: to_time('2021-10-13'))
    ]
  end

  it 'ignores the final artificial change for the purposes of stalled' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status', value: 'Doing', value_id: 12, time: '2021-10-02')
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-08'))).to eq [
      BlockedStalledChange.new(time: to_time('2021-10-01')),
      BlockedStalledChange.new(stalled_days: 6, time: to_time('2021-10-02T01:00:00')),
      BlockedStalledChange.new(stalled_days: 6, time: to_time('2021-10-08T00:00:00'))
    ]
  end

  it 'shows blocked even when there has been a big enough gap to be stalled' do
    issue = empty_issue created: '2021-10-01', board: board
    add_mock_change(issue: issue, field: 'status', value: 'Blocked', value_id: 10, time: '2021-10-02')
    add_mock_change(issue: issue, field: 'status', value: 'In Progress', value_id: 5, time: '2021-10-10')
    expect(stream(issue, settings: settings, end_time: to_time('2021-10-10'))).to eq [
      BlockedStalledChange.new(time: to_time('2021-10-01')),
      BlockedStalledChange.new(status: 'Blocked', time: to_time('2021-10-02')),
      BlockedStalledChange.new(time: to_time('2021-10-10')),
      BlockedStalledChange.new(time: to_time('2021-10-10'))
    ]
  end
end
