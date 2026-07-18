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
end
