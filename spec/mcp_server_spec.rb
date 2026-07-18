# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/mcp_server'

describe McpServer do
  # Board from the complete sample: Ready(10001), In Progress(3), Review(10011), Done(10002).
  let(:board) { load_complete_sample_board }

  # The four filtering handlers read real Issue objects. Build them on the complete-sample board and
  # drive the started/stopped state through a stubbed cycletime (MockCycleTimeConfig keys by issue key,
  # so one config carries every issue at once). started_stopped_times is what sorts an issue into aging
  # (started, not stopped), completed (stopped), or unstarted (neither).
  def handler_issue key:, created:, status_name:, summary: 'Do the thing'
    status = board.possible_statuses.find_all_by_name(status_name).first
    raise "No status named #{status_name}" unless status

    issue = empty_issue created: created, board: board, key: key, creation_status: status
    issue.raw['fields']['summary'] = summary
    issue
  end

  def wire_cycletime(*tuples)
    board.cycletime = mock_cycletime_config stub_values: tuples
  end

  # Each project shares the same today/end_time here — enough for these characterizations.
  def server_context projects:, aggregates: {}, today: '2024-01-15', end_time: '2024-01-15'
    {
      projects: projects.transform_values do |issues|
        { issues: issues, today: to_date(today), end_time: to_time(end_time) }
      end,
      aggregates: aggregates,
      timezone_offset: '+00:00'
    }
  end

  describe '.resolve_projects' do
    it 'returns nil (no filter) when no project is given' do
      expect(described_class.resolve_projects({ aggregates: {} }, nil)).to be_nil
    end

    it 'wraps a plain project name in a one-element allow-list' do
      expect(described_class.resolve_projects({ aggregates: {} }, 'SP')).to eq ['SP']
    end

    it 'expands an aggregate name to its constituent projects' do
      context = { aggregates: { 'Everything' => %w[SP FOO] } }
      expect(described_class.resolve_projects(context, 'Everything')).to eq %w[SP FOO]
    end

    it 'treats a missing aggregates key as no aggregates' do
      expect(described_class.resolve_projects({}, 'SP')).to eq ['SP']
    end
  end

  # time_per_status/column only read a handful of methods off the issue, so drive them with
  # controlled doubles. One day = 86_400 seconds.
  def fake_status name, id: nil
    Data.define(:name, :id).new(name:, id:)
  end

  def fake_change time:, value: nil, value_id: nil, old_value: nil, old_value_id: nil
    Data.define(:time, :value, :value_id, :old_value, :old_value_id)
      .new(time: to_time(time), value:, value_id:, old_value:, old_value_id:)
  end

  def fake_issue created:, status:, changes: [], stopped: nil, issue_board: nil
    Data.define(:status_changes, :started_stopped_times, :created, :status, :board).new(
      status_changes: changes, started_stopped_times: [nil, stopped && to_time(stopped)],
      created: to_time(created), status:, board: issue_board
    )
  end

  describe '.time_per_status' do
    def time_per_status issue, end_time
      described_class.time_per_status(issue, to_time(end_time))
    end

    it 'puts the whole span in the current status when there are no changes' do
      issue = fake_issue created: '2024-01-01', status: fake_status('To Do')
      expect(time_per_status(issue, '2024-01-11')).to eq({ 'To Do' => 864_000.0 }) # 10 days
    end

    it 'records nothing when a change-less issue was created at the end time' do
      issue = fake_issue created: '2024-01-11', status: fake_status('To Do')
      expect(time_per_status(issue, '2024-01-11')).to eq({})
    end

    it 'splits the span across the pre-first, between, and final statuses' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Review'),
        changes: [
          fake_change(time: '2024-01-03', value: 'In Progress', old_value: 'To Do'),
          fake_change(time: '2024-01-06', value: 'Review', old_value: 'In Progress')
        ]
      )
      expect(time_per_status(issue, '2024-01-11')).to eq(
        'To Do' => 172_800.0,        # created -> first change (2 days), from old_value
        'In Progress' => 259_200.0,  # between changes (3 days), from prev value
        'Review' => 432_000.0        # last change -> end (5 days), from last value
      )
    end

    it 'ends the final span at the stop time when the issue stopped before the end time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Done'), stopped: '2024-01-05',
        changes: [fake_change(time: '2024-01-03', value: 'Done', old_value: 'To Do')]
      )
      expect(time_per_status(issue, '2024-01-11')).to eq(
        'To Do' => 172_800.0, 'Done' => 172_800.0 # final span ends at stop (01-03 -> 01-05), not end
      )
    end

    it 'ends the final span at the end time when the issue stopped after it' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Done'), stopped: '2024-01-20',
        changes: [fake_change(time: '2024-01-03', value: 'Done', old_value: 'To Do')]
      )
      expect(time_per_status(issue, '2024-01-11')).to eq(
        'To Do' => 172_800.0, 'Done' => 691_200.0 # final span capped at end (01-03 -> 01-11)
      )
    end

    it 'skips zero-length spans' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('In Progress'),
        changes: [fake_change(time: '2024-01-01', value: 'In Progress', old_value: 'To Do')]
      )
      expect(time_per_status(issue, '2024-01-06')).to eq({ 'In Progress' => 432_000.0 }) # no 'To Do'
    end

    it 'skips a zero-length span between two changes at the same time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('B'),
        changes: [
          fake_change(time: '2024-01-03', value: 'A', old_value: 'To Do'),
          fake_change(time: '2024-01-03', value: 'B', old_value: 'A') # same instant -> 'A' gets nothing
        ]
      )
      expect(time_per_status(issue, '2024-01-06')).to eq('To Do' => 172_800.0, 'B' => 259_200.0)
    end

    it 'skips the final span when the last change lands on the end time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('A'),
        changes: [fake_change(time: '2024-01-03', value: 'A', old_value: 'To Do')]
      )
      expect(time_per_status(issue, '2024-01-03')).to eq({ 'To Do' => 172_800.0 }) # no 'A'
    end
  end

  describe '.time_per_column' do
    def time_per_column issue, end_time
      described_class.time_per_column(issue, to_time(end_time))
    end

    it 'maps each span to its board column via the status id' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Review', id: 10_011), issue_board: board,
        changes: [
          fake_change(time: '2024-01-03', value_id: 3, old_value_id: 10_001),
          fake_change(time: '2024-01-06', value_id: 10_011, old_value_id: 3)
        ]
      )
      expect(time_per_column(issue, '2024-01-11')).to eq(
        'Ready' => 172_800.0,        # old_value_id 10001 -> Ready
        'In Progress' => 259_200.0,  # prev value_id 3 -> In Progress
        'Review' => 432_000.0        # last value_id 10011 -> Review
      )
    end

    it 'falls back to the raw status value when the id maps to no column' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Elsewhere', id: 999_999), issue_board: board,
        changes: []
      )
      expect(time_per_column(issue, '2024-01-11')).to eq({ 'Elsewhere' => 864_000.0 })
    end

    it 'records nothing when a change-less issue was created at the end time' do
      issue = fake_issue created: '2024-01-11', status: fake_status('x', id: 3), issue_board: board
      expect(time_per_column(issue, '2024-01-11')).to eq({})
    end

    it 'uses the status id (not the whole status) to look up a change-less column' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('Ignored Name', id: 3), issue_board: board, changes: []
      )
      expect(time_per_column(issue, '2024-01-11')).to eq({ 'In Progress' => 864_000.0 }) # id 3 -> In Progress
    end

    it 'falls back to raw values at every position when ids map to no column' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('x', id: 666_666), issue_board: board,
        changes: [
          fake_change(time: '2024-01-03', value: 'MidS', value_id: 999_999, old_value: 'InitS', old_value_id: 888_888),
          fake_change(time: '2024-01-06', value: 'FinalS', value_id: 777_777, old_value: 'MidS', old_value_id: 999_999)
        ]
      )
      expect(time_per_column(issue, '2024-01-11')).to eq(
        'InitS' => 172_800.0, 'MidS' => 259_200.0, 'FinalS' => 432_000.0
      )
    end

    it 'skips a zero-length span between two changes at the same time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('r', id: 10_011), issue_board: board,
        changes: [
          fake_change(time: '2024-01-03', value_id: 3, old_value_id: 10_001),
          fake_change(time: '2024-01-03', value_id: 10_011, old_value_id: 3) # same instant -> In Progress gets nothing
        ]
      )
      expect(time_per_column(issue, '2024-01-06')).to eq('Ready' => 172_800.0, 'Review' => 259_200.0)
    end

    it 'skips the final span when the last change lands on the end time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('ip', id: 3), issue_board: board,
        changes: [fake_change(time: '2024-01-03', value_id: 3, old_value_id: 10_001)]
      )
      expect(time_per_column(issue, '2024-01-03')).to eq({ 'Ready' => 172_800.0 }) # no In Progress
    end

    it 'ends the final span at the stop time when the issue stopped before the end time' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('d', id: 10_002), issue_board: board, stopped: '2024-01-05',
        changes: [fake_change(time: '2024-01-03', value_id: 10_002, old_value_id: 10_001)]
      )
      expect(time_per_column(issue, '2024-01-11')).to eq('Ready' => 172_800.0, 'Done' => 172_800.0) # 01-03->01-05
    end

    it 'ends the final span at the end time when the issue stopped after it' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('d', id: 10_002), issue_board: board, stopped: '2024-01-20',
        changes: [fake_change(time: '2024-01-03', value_id: 10_002, old_value_id: 10_001)]
      )
      expect(time_per_column(issue, '2024-01-11')).to eq('Ready' => 172_800.0, 'Done' => 691_200.0) # 01-03->01-11
    end

    it 'skips a zero-length initial span' do
      issue = fake_issue(
        created: '2024-01-01', status: fake_status('ip', id: 3), issue_board: board,
        changes: [fake_change(time: '2024-01-01', value_id: 3, old_value_id: 10_001)] # change at creation
      )
      expect(time_per_column(issue, '2024-01-06')).to eq({ 'In Progress' => 432_000.0 }) # no Ready
    end
  end

  describe '.column_name_for' do
    it 'returns the visible column that owns the status id' do
      expect(described_class.column_name_for(board, 3)).to eq 'In Progress'
    end

    it 'returns nil when no visible column owns the status id' do
      expect(described_class.column_name_for(board, 999_999)).to be_nil
    end
  end

  describe '.matches_blocked_stalled?' do
    # bsc entries only need to answer blocked?/stalled?
    def change blocked: false, stalled: false
      Struct.new(:is_blocked, :is_stalled) do
        def blocked? = is_blocked
        def stalled? = is_stalled
      end.new(blocked, stalled)
    end

    def matches? bsc, ever_blocked: nil, ever_stalled: nil, currently_blocked: nil, currently_stalled: nil
      McpServer.matches_blocked_stalled?(bsc, ever_blocked, ever_stalled, currently_blocked, currently_stalled)
    end

    it 'matches everything when no blocked/stalled filter is set' do
      expect(matches?([])).to be true
    end

    it 'ever_blocked requires at least one blocked entry' do
      aggregate_failures do
        expect(matches?([change(blocked: true)], ever_blocked: true)).to be true
        expect(matches?([change(blocked: false)], ever_blocked: true)).to be false
        expect(matches?([], ever_blocked: true)).to be false
      end
    end

    it 'ever_stalled requires at least one stalled entry' do
      aggregate_failures do
        expect(matches?([change(stalled: true)], ever_stalled: true)).to be true
        expect(matches?([change(stalled: false)], ever_stalled: true)).to be false
      end
    end

    it 'currently_blocked requires the LAST entry to be blocked' do
      aggregate_failures do
        expect(matches?([change(blocked: false), change(blocked: true)], currently_blocked: true)).to be true
        expect(matches?([change(blocked: true), change(blocked: false)], currently_blocked: true)).to be false
        expect(matches?([], currently_blocked: true)).to be false # last is nil
      end
    end

    it 'currently_stalled requires the LAST entry to be stalled' do
      aggregate_failures do
        expect(matches?([change(stalled: true)], currently_stalled: true)).to be true
        expect(matches?([change(stalled: false)], currently_stalled: true)).to be false
        expect(matches?([], currently_stalled: true)).to be false # last is nil
      end
    end
  end

  describe '.flow_efficiency_percent' do
    def flow active, total
      time = to_time('2024-01-01')
      issue = instance_double(Issue)
      allow(issue).to receive(:flow_efficiency_numbers).with(end_time: time).and_return([active, total])
      described_class.flow_efficiency_percent(issue, time)
    end

    it 'returns active/total as a percentage rounded to one decimal' do
      expect(flow(1.0, 3.0)).to eq 33.3 # 1/3 * 100, rounded to 1dp (not 33, not 33.33)
    end

    it 'returns nil when there is no total time' do
      aggregate_failures do
        expect(flow(0.0, 0.0)).to be_nil   # zero
        expect(flow(1.0, -1.0)).to be_nil  # negative
      end
    end
  end

  describe '.matches_history?' do
    def hist_change field:, value:
      Data.define(:field, :value).new(field:, value:)
    end

    def bsc_change blocked: false, stalled: false
      Struct.new(:is_blocked, :is_stalled) do
        def blocked? = is_blocked
        def stalled? = is_stalled
      end.new(blocked, stalled)
    end

    def matches? changes: [], bsc: [], **flags
      time = to_time('2024-01-01')
      issue = instance_double(Issue, changes: changes)
      allow(issue).to receive(:blocked_stalled_changes).with(end_time: time).and_return(bsc)
      described_class.matches_history?(
        issue, time,
        flags[:history_field], flags[:history_value],
        flags[:ever_blocked], flags[:ever_stalled], flags[:currently_blocked], flags[:currently_stalled]
      )
    end

    it 'matches when no filters are set' do
      expect(matches?).to be true
    end

    it 'applies the history filter only when both a field and a value are given' do
      aggregate_failures do
        expect(matches?(history_field: 'priority')).to be true # value missing -> filter skipped
        expect(matches?(history_value: 'High')).to be true     # field missing -> filter skipped
      end
    end

    it 'requires some change to have matched the history field AND value' do
      matching = [hist_change(field: 'priority', value: 'High')]
      aggregate_failures do
        expect(matches?(changes: matching, history_field: 'priority', history_value: 'High')).to be true
        expect(matches?(changes: matching, history_field: 'priority', history_value: 'Low')).to be false # value
        expect(matches?(changes: matching, history_field: 'status', history_value: 'High')).to be false  # field
        expect(matches?(changes: [], history_field: 'priority', history_value: 'High')).to be false
      end
    end

    it 'delegates to the blocked/stalled predicate when any blocked/stalled flag is set' do
      # each flag independently enters the block, so each arm of the || guard is exercised
      aggregate_failures do
        expect(matches?(bsc: [bsc_change(blocked: true)], ever_blocked: true)).to be true
        expect(matches?(bsc: [bsc_change(blocked: false)], ever_blocked: true)).to be false
        expect(matches?(bsc: [bsc_change(stalled: true)], ever_stalled: true)).to be true
        expect(matches?(bsc: [bsc_change(stalled: false)], ever_stalled: true)).to be false
        expect(matches?(bsc: [bsc_change(blocked: true)], currently_blocked: true)).to be true
        expect(matches?(bsc: [bsc_change(blocked: false)], currently_blocked: true)).to be false
        expect(matches?(bsc: [bsc_change(stalled: true)], currently_stalled: true)).to be true
        expect(matches?(bsc: [bsc_change(stalled: false)], currently_stalled: true)).to be false
      end
    end
  end

  describe McpServer::ListProjectsTool do
    # ListProjectsTool only reads issues.size, so the issue objects can be anything countable.
    # **context lets a test omit the :aggregates key entirely (exercises the `|| {}` fallback).
    def call_context(**context)
      described_class.call(server_context: context)
    end

    it 'lists each project with its issue count and data end date as a text response' do
      response = call_context(
        projects: {
          'SP' => { issues: [1, 2, 3], today: to_date('2024-01-15') },
          'FOO' => { issues: [1], today: to_date('2024-01-10') }
        },
        aggregates: {}
      )
      expect(response.content).to eq [{
        type: 'text',
        text: "SP | 3 issues | Data through: 2024-01-15\nFOO | 1 issues | Data through: 2024-01-10"
      }]
    end

    it 'appends aggregate groups, comma-joined, when present' do
      text = call_context(
        projects: { 'SP' => { issues: [1], today: to_date('2024-01-15') } },
        aggregates: { 'Everything' => %w[SP FOO] }
      ).content.first[:text]
      expect(text).to eq(
        "SP | 1 issues | Data through: 2024-01-15\n" \
        "\n" \
        "Aggregate groups (can be used as a project filter):\n" \
        'Everything | includes: SP, FOO'
      )
    end

    it 'omits the aggregate section when the context has no aggregates key' do
      text = call_context(projects: { 'SP' => { issues: [1], today: to_date('2024-01-15') } }).content.first[:text]
      expect(text).to eq 'SP | 1 issues | Data through: 2024-01-15'
    end
  end

  describe McpServer::AgingWorkTool do
    def aging_text context, **args
      described_class.call(server_context: context, **args).content.first[:text]
    end

    it 'formats a started, unfinished issue as one line with age and flow efficiency' do
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress'
      wire_cycletime [issue, '2024-01-05', nil]
      response = described_class.call(server_context: server_context(projects: { 'SP' => [issue] }))
      # Age = (today 01-15 - started 01-05) + 1 = 11 days. FE 100% because the whole window is active.
      expect(response.content).to eq [{
        type: 'text',
        text: 'SP-1 | SP | Bug | In Progress | Age: 11d | FE: 100.0% | Do the thing'
      }]
    end

    it 'includes only started, unfinished issues (excluding unstarted and completed ones ahead of them)' do
      completed = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'completed'
      unstarted = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'unstarted'
      aging = handler_issue key: 'SP-3', created: '2024-01-01', status_name: 'In Progress', summary: 'aging'
      wire_cycletime [completed, '2024-01-05', '2024-01-10'], [unstarted, nil, nil], [aging, '2024-01-05', nil]
      # completed and unstarted are dropped even though they come first in iteration order.
      text = aging_text(server_context(projects: { 'SP' => [completed, unstarted, aging] }))
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[aging]
    end

    it 'returns a not-found message when no issue is aging' do
      completed = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done'
      wire_cycletime [completed, '2024-01-05', '2024-01-10']
      expect(aging_text(server_context(projects: { 'SP' => [completed] }))).to eq 'No aging work found.'
    end

    it 'sorts oldest (highest age) first' do
      younger = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'younger'
      older = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'older'
      wire_cycletime [younger, '2024-01-10', nil], [older, '2024-01-03', nil]
      text = aging_text(server_context(projects: { 'SP' => [younger, older] }))
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[older younger]
    end

    it 'filters out issues younger than min_age_days' do
      young = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'young'
      old = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'old'
      wire_cycletime [young, '2024-01-14', nil], [old, '2024-01-05', nil]
      # young age = (15-14)+1 = 2; old age = 11. min_age_days 3 keeps only old.
      text = aging_text(server_context(projects: { 'SP' => [young, old] }), min_age_days: 3)
      expect(text).to eq 'SP-2 | SP | Bug | In Progress | Age: 11d | FE: 100.0% | old'
    end

    it 'filters by current_status' do
      in_progress = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'ip'
      review = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Review', summary: 'rev'
      wire_cycletime [in_progress, '2024-01-05', nil], [review, '2024-01-05', nil]
      text = aging_text(server_context(projects: { 'SP' => [in_progress, review] }), current_status: 'Review')
      expect(text).to eq 'SP-2 | SP | Bug | Review | Age: 11d | FE: 100.0% | rev'
    end

    it 'filters by current_column (status id mapped through the board)' do
      review = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Review', summary: 'rev'
      in_progress = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'ip'
      wire_cycletime [review, '2024-01-05', nil], [in_progress, '2024-01-05', nil]
      # The excluded Review issue comes first, so a break (rather than skip) would wrongly drop the match.
      text = aging_text(server_context(projects: { 'SP' => [review, in_progress] }), current_column: 'In Progress')
      expect(text).to eq 'SP-2 | SP | Bug | In Progress | Age: 11d | FE: 100.0% | ip'
    end

    it 'restricts to the named project, accepting the project_name alias' do
      sp_issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'sp'
      foo_issue = handler_issue key: 'FOO-1', created: '2024-01-01', status_name: 'In Progress', summary: 'foo'
      wire_cycletime [sp_issue, '2024-01-05', nil], [foo_issue, '2024-01-05', nil]
      context = server_context(projects: { 'SP' => [sp_issue], 'FOO' => [foo_issue] })
      expect(aging_text(context, project_name: 'FOO'))
        .to eq 'FOO-1 | FOO | Bug | In Progress | Age: 11d | FE: 100.0% | foo'
    end

    it 'expands an aggregate name to its constituent projects' do
      sp_issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'sp'
      foo_issue = handler_issue key: 'FOO-1', created: '2024-01-01', status_name: 'In Progress', summary: 'foo'
      bar_issue = handler_issue key: 'BAR-1', created: '2024-01-01', status_name: 'In Progress', summary: 'bar'
      wire_cycletime [sp_issue, '2024-01-05', nil], [foo_issue, '2024-01-05', nil], [bar_issue, '2024-01-05', nil]
      context = server_context(
        projects: { 'SP' => [sp_issue], 'FOO' => [foo_issue], 'BAR' => [bar_issue] },
        aggregates: { 'Some' => %w[SP FOO] }
      )
      text = aging_text(context, project: 'Some')
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to contain_exactly('sp', 'foo')
    end

    it 'applies the history filter, keeping only issues whose change history matched' do
      unmatched = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'unmatched'
      matched = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'matched'
      add_mock_change(issue: matched, field: 'priority', value: 'High', time: '2024-01-02')
      wire_cycletime [unmatched, '2024-01-05', nil], [matched, '2024-01-05', nil]
      # The unmatched issue is first, so a break would wrongly drop the matching one behind it.
      context = server_context(projects: { 'SP' => [unmatched, matched] })
      text = aging_text(context, history_field: 'priority', history_value: 'High')
      expect(text).to eq 'SP-2 | SP | Bug | In Progress | Age: 11d | FE: 100.0% | matched'
    end

    # These four exercise each blocked/stalled flag through the handler, proving it forwards the flag
    # (and the data end_time) into matches_history?. A blocked issue is one with a Flagged change;
    # a stalled issue is one left inactive past the stalled threshold (5 days).
    it 'filters by ever_blocked' do
      blocked = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'blocked'
      add_mock_change(issue: blocked, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      clear = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'clear'
      add_mock_change(issue: clear, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-14')
      wire_cycletime [blocked, '2024-01-05', nil], [clear, '2024-01-05', nil]
      text = aging_text(server_context(projects: { 'SP' => [blocked, clear] }), ever_blocked: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[blocked]
    end

    it 'filters by currently_blocked' do
      still = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'still'
      add_mock_change(issue: still, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      cleared = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'cleared'
      add_mock_change(issue: cleared, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      add_mock_change(issue: cleared, field: 'Flagged', value: '', time: '2024-01-08')
      wire_cycletime [still, '2024-01-05', nil], [cleared, '2024-01-05', nil]
      # 'cleared' was blocked earlier but unflagged before the end date, so only 'still' is current.
      text = aging_text(server_context(projects: { 'SP' => [still, cleared] }), currently_blocked: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[still]
    end

    it 'filters by ever_stalled' do
      stalled = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'stalled'
      add_mock_change(issue: stalled, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-02')
      active = handler_issue key: 'SP-2', created: '2024-01-13', status_name: 'In Progress', summary: 'active'
      wire_cycletime [stalled, '2024-01-02', nil], [active, '2024-01-13', nil]
      # 'stalled' sat untouched from 01-02 to the 01-15 end date (>5 days); 'active' was created 01-13.
      text = aging_text(server_context(projects: { 'SP' => [stalled, active] }), ever_stalled: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[stalled]
    end

    it 'filters by currently_stalled' do
      stalled = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'stalled'
      add_mock_change(issue: stalled, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-02')
      revived = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'revived'
      add_mock_change(issue: revived, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-14')
      wire_cycletime [stalled, '2024-01-02', nil], [revived, '2024-01-01', nil]
      # 'revived' stalled early but had activity on 01-14, so it is not stalled as of the 01-15 end date.
      text = aging_text(server_context(projects: { 'SP' => [stalled, revived] }), currently_stalled: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[stalled]
    end

    it 'omits the flow-efficiency segment when it cannot be computed' do
      # Started after the data end_time -> flow_efficiency_numbers returns no total, so FE is nil.
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress'
      wire_cycletime [issue, '2024-01-20', nil]
      text = aging_text(server_context(projects: { 'SP' => [issue] }, today: '2024-01-25', end_time: '2024-01-15'))
      expect(text).to eq 'SP-1 | SP | Bug | In Progress | Age: 6d | Do the thing'
    end
  end

  describe McpServer::CompletedWorkTool do
    def completed_text context, **args
      described_class.call(server_context: context, **args).content.first[:text]
    end

    it 'formats a completed issue with cycle time, flow efficiency, and completion status' do
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done'
      wire_cycletime [issue, '2024-01-05', '2024-01-10']
      response = described_class.call(server_context: server_context(projects: { 'SP' => [issue] }))
      # Cycle time = (stopped 01-10 - started 01-05) + 1 = 6 days. Completion is the status at done ('Done').
      expect(response.content).to eq [{
        type: 'text',
        text: 'SP-1 | SP | Bug | 2024-01-10 | Cycle time: 6d | FE: 100.0% | Done | Do the thing'
      }]
    end

    it 'includes only stopped issues, even when an unfinished one comes first' do
      aging = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress', summary: 'aging'
      completed = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Done', summary: 'completed'
      wire_cycletime [aging, '2024-01-05', nil], [completed, '2024-01-05', '2024-01-10']
      text = completed_text(server_context(projects: { 'SP' => [aging, completed] }))
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[completed]
    end

    it 'returns a not-found message when nothing has completed' do
      aging = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress'
      wire_cycletime [aging, '2024-01-05', nil]
      expect(completed_text(server_context(projects: { 'SP' => [aging] }))).to eq 'No completed work found.'
    end

    it 'sorts most recently completed first' do
      older = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'older'
      newer = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Done', summary: 'newer'
      wire_cycletime [older, '2024-01-05', '2024-01-08'], [newer, '2024-01-05', '2024-01-12']
      text = completed_text(server_context(projects: { 'SP' => [older, newer] }))
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[newer older]
    end

    it 'restricts to the named project, accepting the project_name alias' do
      sp_issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'sp'
      foo_issue = handler_issue key: 'FOO-1', created: '2024-01-01', status_name: 'Done', summary: 'foo'
      wire_cycletime [sp_issue, '2024-01-05', '2024-01-10'], [foo_issue, '2024-01-05', '2024-01-10']
      context = server_context(projects: { 'SP' => [sp_issue], 'FOO' => [foo_issue] })
      expect(completed_text(context, project_name: 'FOO').split(' | ')).to include('FOO-1', 'foo')
    end

    it 'filters out issues completed before the days_back cutoff' do
      recent = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'recent'
      old = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Done', summary: 'old'
      wire_cycletime [recent, '2024-01-05', '2024-01-12'], [old, '2024-01-05', '2024-01-08']
      # today 01-15, days_back 5 -> cutoff 01-10; 'old' completed 01-08 falls before it.
      text = completed_text(server_context(projects: { 'SP' => [recent, old] }), days_back: 5)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[recent]
    end

    it 'filters by completed_status (the status the issue was in when it finished)' do
      done = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'done'
      review = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Review', summary: 'review'
      wire_cycletime [done, '2024-01-05', '2024-01-10'], [review, '2024-01-05', '2024-01-10']
      text = completed_text(server_context(projects: { 'SP' => [done, review] }), completed_status: 'Done')
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[done]
    end

    it 'filters by completed_resolution (matched by value, not identity) and joins status with resolution' do
      resolved = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'resolved'
      add_mock_change(issue: resolved, field: 'resolution', value: "Won't Do", time: '2024-01-09')
      unresolved = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Done', summary: 'unresolved'
      wire_cycletime [resolved, '2024-01-05', '2024-01-10'], [unresolved, '2024-01-05', '2024-01-10']
      # The filter value is a distinct string object from the one on the change, so an identity (equal?)
      # comparison would wrongly reject it — the match must be by value.
      filter = +"Won't Do"
      text = completed_text(server_context(projects: { 'SP' => [resolved, unresolved] }), completed_resolution: filter)
      expect(text).to eq "SP-1 | SP | Bug | 2024-01-10 | Cycle time: 6d | FE: 100.0% | Done / Won't Do | resolved"
    end

    it 'keeps resolved issues (and shows the resolution) when no resolution filter is given' do
      resolved = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'resolved'
      add_mock_change(issue: resolved, field: 'resolution', value: 'Fixed', time: '2024-01-09')
      wire_cycletime [resolved, '2024-01-05', '2024-01-10']
      text = completed_text(server_context(projects: { 'SP' => [resolved] }))
      expect(text).to eq 'SP-1 | SP | Bug | 2024-01-10 | Cycle time: 6d | FE: 100.0% | Done / Fixed | resolved'
    end

    it 'reports unknown cycle time and omits flow efficiency when the issue never started' do
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done'
      wire_cycletime [issue, nil, '2024-01-10']
      text = completed_text(server_context(projects: { 'SP' => [issue] }))
      expect(text).to eq 'SP-1 | SP | Bug | 2024-01-10 | Cycle time: unknown | Done | Do the thing'
    end

    it 'applies the history filter' do
      matched = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'matched'
      add_mock_change(issue: matched, field: 'priority', value: 'High', time: '2024-01-02')
      unmatched = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Done', summary: 'unmatched'
      wire_cycletime [matched, '2024-01-05', '2024-01-10'], [unmatched, '2024-01-05', '2024-01-10']
      context = server_context(projects: { 'SP' => [matched, unmatched] })
      text = completed_text(context, history_field: 'priority', history_value: 'High')
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[matched]
    end

    # As with aging work, each blocked/stalled flag must be forwarded (with the data end_time) into
    # matches_history?. Here the issues are all completed (they carry a stop time).
    it 'filters by ever_blocked' do
      blocked = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'blocked'
      add_mock_change(issue: blocked, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      clear = handler_issue key: 'SP-2', created: '2024-01-13', status_name: 'Done', summary: 'clear'
      wire_cycletime [blocked, '2024-01-05', '2024-01-10'], [clear, '2024-01-13', '2024-01-14']
      text = completed_text(server_context(projects: { 'SP' => [blocked, clear] }), ever_blocked: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[blocked]
    end

    it 'filters by currently_blocked' do
      still = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'still'
      add_mock_change(issue: still, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      cleared = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Done', summary: 'cleared'
      add_mock_change(issue: cleared, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      add_mock_change(issue: cleared, field: 'Flagged', value: '', time: '2024-01-08')
      wire_cycletime [still, '2024-01-05', '2024-01-10'], [cleared, '2024-01-05', '2024-01-10']
      text = completed_text(server_context(projects: { 'SP' => [still, cleared] }), currently_blocked: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[still]
    end

    it 'filters by ever_stalled' do
      stalled = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'stalled'
      add_mock_change(issue: stalled, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-02')
      active = handler_issue key: 'SP-2', created: '2024-01-13', status_name: 'Done', summary: 'active'
      wire_cycletime [stalled, '2024-01-02', '2024-01-10'], [active, '2024-01-13', '2024-01-14']
      text = completed_text(server_context(projects: { 'SP' => [stalled, active] }), ever_stalled: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[stalled]
    end

    it 'filters by currently_stalled' do
      stalled = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done', summary: 'stalled'
      add_mock_change(issue: stalled, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-02')
      revived = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Done', summary: 'revived'
      add_mock_change(issue: revived, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-14')
      wire_cycletime [stalled, '2024-01-02', '2024-01-10'], [revived, '2024-01-01', '2024-01-10']
      text = completed_text(server_context(projects: { 'SP' => [stalled, revived] }), currently_stalled: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[stalled]
    end
  end

  describe McpServer::NotYetStartedTool do
    def unstarted_text context, **args
      described_class.call(server_context: context, **args).content.first[:text]
    end

    it 'formats an unstarted issue with its creation date' do
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog'
      wire_cycletime [issue, nil, nil]
      response = described_class.call(server_context: server_context(projects: { 'SP' => [issue] }))
      expect(response.content).to eq [{
        type: 'text',
        text: 'SP-1 | SP | Bug | Backlog | Created: 2024-01-01 | Do the thing'
      }]
    end

    it 'includes only issues that are neither started nor stopped, even when excluded ones come first' do
      started = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'started'
      stopped = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Backlog', summary: 'stopped'
      completed = handler_issue key: 'SP-3', created: '2024-01-01', status_name: 'Backlog', summary: 'completed'
      unstarted = handler_issue key: 'SP-4', created: '2024-01-01', status_name: 'Backlog', summary: 'unstarted'
      wire_cycletime(
        [started, '2024-01-05', nil], [stopped, nil, '2024-01-10'],
        [completed, '2024-01-05', '2024-01-10'], [unstarted, nil, nil]
      )
      text = unstarted_text(server_context(projects: { 'SP' => [started, stopped, completed, unstarted] }))
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[unstarted]
    end

    it 'returns a not-found message when everything has started' do
      started = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog'
      wire_cycletime [started, '2024-01-05', nil]
      expect(unstarted_text(server_context(projects: { 'SP' => [started] }))).to eq 'No unstarted work found.'
    end

    it 'sorts by creation date, oldest first' do
      newer = handler_issue key: 'SP-1', created: '2024-01-10', status_name: 'Backlog', summary: 'newer'
      older = handler_issue key: 'SP-2', created: '2024-01-03', status_name: 'Backlog', summary: 'older'
      wire_cycletime [newer, nil, nil], [older, nil, nil]
      text = unstarted_text(server_context(projects: { 'SP' => [newer, older] }))
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[older newer]
    end

    it 'restricts to the named project, accepting the project_name alias' do
      sp_issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'sp'
      foo_issue = handler_issue key: 'FOO-1', created: '2024-01-01', status_name: 'Backlog', summary: 'foo'
      wire_cycletime [sp_issue, nil, nil], [foo_issue, nil, nil]
      context = server_context(projects: { 'SP' => [sp_issue], 'FOO' => [foo_issue] })
      expect(unstarted_text(context, project_name: 'FOO'))
        .to eq 'FOO-1 | FOO | Bug | Backlog | Created: 2024-01-01 | foo'
    end

    it 'expands an aggregate name to its constituent projects' do
      sp_issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'sp'
      foo_issue = handler_issue key: 'FOO-1', created: '2024-01-01', status_name: 'Backlog', summary: 'foo'
      bar_issue = handler_issue key: 'BAR-1', created: '2024-01-01', status_name: 'Backlog', summary: 'bar'
      wire_cycletime [sp_issue, nil, nil], [foo_issue, nil, nil], [bar_issue, nil, nil]
      context = server_context(
        projects: { 'SP' => [sp_issue], 'FOO' => [foo_issue], 'BAR' => [bar_issue] },
        aggregates: { 'Some' => %w[SP FOO] }
      )
      text = unstarted_text(context, project: 'Some')
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to contain_exactly('sp', 'foo')
    end

    it 'filters by current_status (excluded issue first)' do
      backlog = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'backlog'
      review = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Review', summary: 'review'
      wire_cycletime [backlog, nil, nil], [review, nil, nil]
      text = unstarted_text(server_context(projects: { 'SP' => [backlog, review] }), current_status: 'Review')
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[review]
    end

    it 'filters by current_column (excluded issue first)' do
      review = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Review', summary: 'review'
      in_progress = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress', summary: 'ip'
      wire_cycletime [review, nil, nil], [in_progress, nil, nil]
      text = unstarted_text(server_context(projects: { 'SP' => [review, in_progress] }), current_column: 'In Progress')
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[ip]
    end

    it 'applies the history filter, keeping only issues whose change history matched (unmatched first)' do
      unmatched = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'unmatched'
      matched = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Backlog', summary: 'matched'
      add_mock_change(issue: matched, field: 'priority', value: 'High', time: '2024-01-02')
      wire_cycletime [unmatched, nil, nil], [matched, nil, nil]
      context = server_context(projects: { 'SP' => [unmatched, matched] })
      text = unstarted_text(context, history_field: 'priority', history_value: 'High')
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[matched]
    end

    # Blocked/stalled forwarding, on unstarted issues (their history still records flags and gaps).
    it 'filters by ever_blocked' do
      blocked = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'blocked'
      add_mock_change(issue: blocked, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      clear = handler_issue key: 'SP-2', created: '2024-01-13', status_name: 'Backlog', summary: 'clear'
      wire_cycletime [blocked, nil, nil], [clear, nil, nil]
      text = unstarted_text(server_context(projects: { 'SP' => [blocked, clear] }), ever_blocked: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[blocked]
    end

    it 'filters by currently_blocked' do
      still = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'still'
      add_mock_change(issue: still, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      cleared = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Backlog', summary: 'cleared'
      add_mock_change(issue: cleared, field: 'Flagged', value: 'Blocked', time: '2024-01-06')
      add_mock_change(issue: cleared, field: 'Flagged', value: '', time: '2024-01-08')
      wire_cycletime [still, nil, nil], [cleared, nil, nil]
      text = unstarted_text(server_context(projects: { 'SP' => [still, cleared] }), currently_blocked: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[still]
    end

    it 'filters by ever_stalled' do
      stalled = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'stalled'
      add_mock_change(issue: stalled, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-02')
      active = handler_issue key: 'SP-2', created: '2024-01-13', status_name: 'Backlog', summary: 'active'
      wire_cycletime [stalled, nil, nil], [active, nil, nil]
      text = unstarted_text(server_context(projects: { 'SP' => [stalled, active] }), ever_stalled: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[stalled]
    end

    it 'filters by currently_stalled' do
      stalled = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Backlog', summary: 'stalled'
      add_mock_change(issue: stalled, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-02')
      revived = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'Backlog', summary: 'revived'
      add_mock_change(issue: revived, field: 'status', value: 'In Progress', value_id: 3, time: '2024-01-14')
      wire_cycletime [stalled, nil, nil], [revived, nil, nil]
      text = unstarted_text(server_context(projects: { 'SP' => [stalled, revived] }), currently_stalled: true)
      expect(text.lines.map { |line| line.split(' | ').last.chomp }).to eq %w[stalled]
    end
  end

  describe McpServer::StatusTimeAnalysisTool do
    describe '.select_issues' do
      def selects? issue_state, started:, stopped:
        issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress'
        wire_cycletime [issue, started, stopped]
        described_class.select_issues(issue, issue_state)
      end

      # The result only ever feeds an `unless` guard, so its contract is truthiness, not a strict boolean.
      it "'aging' selects issues that are started but not stopped" do
        aggregate_failures do
          expect(selects?('aging', started: '2024-01-05', stopped: nil)).to be_truthy
          expect(selects?('aging', started: '2024-01-05', stopped: '2024-01-10')).to be_falsey
          expect(selects?('aging', started: nil, stopped: nil)).to be_falsey
        end
      end

      it "'completed' selects any stopped issue" do
        aggregate_failures do
          expect(selects?('completed', started: '2024-01-05', stopped: '2024-01-10')).to be_truthy
          expect(selects?('completed', started: nil, stopped: '2024-01-10')).to be_truthy
          expect(selects?('completed', started: '2024-01-05', stopped: nil)).to be_falsey
        end
      end

      it "'not_started' selects issues that are neither started nor stopped" do
        aggregate_failures do
          expect(selects?('not_started', started: nil, stopped: nil)).to be_truthy
          expect(selects?('not_started', started: '2024-01-05', stopped: nil)).to be_falsey
          expect(selects?('not_started', started: nil, stopped: '2024-01-10')).to be_falsey
        end
      end

      it "'all' (and any other value) selects every issue" do
        aggregate_failures do
          expect(selects?('all', started: nil, stopped: nil)).to be_truthy
          expect(selects?('all', started: '2024-01-05', stopped: '2024-01-10')).to be_truthy
        end
      end
    end

    def analysis_text context, **args
      described_class.call(server_context: context, **args).content.first[:text]
    end

    it 'reports average, total, and issue count per status, grouped by status name' do
      # No status changes, so the whole span (created 01-01 -> end 01-15 = 14 days) sits in the current status.
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress'
      wire_cycletime [issue, nil, nil]
      response = described_class.call(server_context: server_context(projects: { 'SP' => [issue] }))
      expect(response.content).to eq [{
        type: 'text',
        text: 'Status: In Progress | Avg: 14.0d | Total: 14.0d | Issues: 1'
      }]
    end

    it 'averages the total time across the issues that visited a status' do
      long = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress'
      short = handler_issue key: 'SP-2', created: '2024-01-11', status_name: 'In Progress'
      wire_cycletime [long, nil, nil], [short, nil, nil]
      # 14 days + 4 days = 18 total, averaged over 2 issues = 9.
      text = analysis_text(server_context(projects: { 'SP' => [long, short] }))
      expect(text).to eq 'Status: In Progress | Avg: 9.0d | Total: 18.0d | Issues: 2'
    end

    it 'groups by status name (not board column) by default' do
      # Status id 10001 is named 'Selected for Development' but lives in the 'Ready' column, so the
      # grouping key reveals whether time_per_status (name) or time_per_column (column) was used.
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Selected for Development'
      wire_cycletime [issue, nil, nil]
      text = analysis_text(server_context(projects: { 'SP' => [issue] }))
      expect(text).to eq 'Status: Selected for Development | Avg: 14.0d | Total: 14.0d | Issues: 1'
    end

    it 'groups by board column, and labels rows Column, when group_by is column' do
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Selected for Development'
      wire_cycletime [issue, nil, nil]
      text = analysis_text(server_context(projects: { 'SP' => [issue] }), group_by: 'column')
      expect(text).to eq 'Column: Ready | Avg: 14.0d | Total: 14.0d | Issues: 1'
    end

    it 'forces column grouping when the column alias parameter is given' do
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Selected for Development'
      wire_cycletime [issue, nil, nil]
      text = analysis_text(server_context(projects: { 'SP' => [issue] }), column: 'ignored')
      expect(text).to eq 'Column: Ready | Avg: 14.0d | Total: 14.0d | Issues: 1'
    end

    it 'restricts issues to the requested state (dropping excluded ones ahead of kept ones)' do
      completed = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Review'
      aging = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress'
      wire_cycletime [completed, '2024-01-05', '2024-01-10'], [aging, '2024-01-05', nil]
      # 'completed' is excluded and comes first, so a break rather than a skip would lose 'aging' behind it.
      text = analysis_text(server_context(projects: { 'SP' => [completed, aging] }), issue_state: 'aging')
      expect(text).to eq 'Status: In Progress | Avg: 14.0d | Total: 14.0d | Issues: 1'
    end

    it 'rounds average and total days to one decimal place' do
      # created 01-01 00:00 -> end 01-15 08:00 = 14 days 8 hours = 14.333... days.
      issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress'
      wire_cycletime [issue, nil, nil]
      text = analysis_text(server_context(projects: { 'SP' => [issue] }, end_time: '2024-01-15T08:00:00'))
      expect(text).to eq 'Status: In Progress | Avg: 14.3d | Total: 14.3d | Issues: 1'
    end

    it 'restricts to the named project' do
      sp_issue = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'In Progress'
      foo_issue = handler_issue key: 'FOO-1', created: '2024-01-11', status_name: 'Review'
      wire_cycletime [sp_issue, nil, nil], [foo_issue, nil, nil]
      context = server_context(projects: { 'SP' => [sp_issue], 'FOO' => [foo_issue] })
      expect(analysis_text(context, project_name: 'FOO')).to eq 'Status: Review | Avg: 4.0d | Total: 4.0d | Issues: 1'
    end

    it 'sorts rows by descending average time' do
      # Insert the quicker status first so insertion order differs from the sorted (descending) order.
      quick = handler_issue key: 'SP-1', created: '2024-01-11', status_name: 'Review'
      slow = handler_issue key: 'SP-2', created: '2024-01-01', status_name: 'In Progress'
      wire_cycletime [quick, nil, nil], [slow, nil, nil]
      text = analysis_text(server_context(projects: { 'SP' => [quick, slow] }))
      expect(text.lines.map(&:chomp)).to eq [
        'Status: In Progress | Avg: 14.0d | Total: 14.0d | Issues: 1',
        'Status: Review | Avg: 4.0d | Total: 4.0d | Issues: 1'
      ]
    end

    it 'returns a not-found message when no issue contributes any time' do
      completed = handler_issue key: 'SP-1', created: '2024-01-01', status_name: 'Done'
      wire_cycletime [completed, '2024-01-05', '2024-01-10']
      response = described_class.call(
        server_context: server_context(projects: { 'SP' => [completed] }), issue_state: 'aging'
      )
      expect(response.content).to eq [{ type: 'text', text: 'No data found.' }]
    end
  end
end
