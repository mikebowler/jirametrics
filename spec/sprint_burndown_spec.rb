# frozen_string_literal: true

require './spec/spec_helper'

describe SprintBurndown do
  let(:board) { load_complete_sample_board }
  let(:sprint_burndown) do
    described_class.new.tap do |chart|
      # Larger than the sprint
      chart.time_range = to_time('2022-03-01')..to_time('2022-04-11T23:59:59 +00:00')
      chart.date_range = chart.time_range.begin.to_date..chart.time_range.end.to_date
      chart.all_boards = { board.id => board }
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

  describe '#options=' do
    it 'handles points_only' do
      sprint_burndown.options = :points_only
      expect([sprint_burndown.use_story_points, sprint_burndown.use_story_counts]).to eq([true, false])
    end

    it 'handles counts_only' do
      sprint_burndown.options = :counts_only
      expect([sprint_burndown.use_story_points, sprint_burndown.use_story_counts]).to eq([false, true])
    end

    it 'handles points_and_counts' do
      sprint_burndown.options = :points_and_counts
      expect([sprint_burndown.use_story_points, sprint_burndown.use_story_counts]).to eq([true, true])
    end

    it 'handles neither' do
      expect { sprint_burndown.options = :foo }.to raise_error 'Unexpected option: foo'
    end
  end

  describe '#run' do
    let(:scrum_board) do
      load_complete_sample_board.tap do |b|
        b.raw['type'] = 'scrum'
        b.sprints << Sprint.new(
          raw: {
            'id' => 1, 'state' => 'active', 'name' => 'Sprint One',
            'activatedDate' => '2022-03-05T00:00:00z', 'endDate' => '2022-03-20T00:00:00z'
          },
          timezone_offset: '+00:00'
        )
      end
    end

    let(:scrum_chart) do
      described_class.new.tap do |chart|
        chart.time_range = to_time('2022-03-01')..to_time('2022-03-31T23:59:59 +00:00')
        chart.date_range = chart.time_range.begin.to_date..chart.time_range.end.to_date
        chart.all_boards = { scrum_board.id => scrum_board }
        chart.board_id = scrum_board.id
        chart.file_system = MockFileSystem.new
        chart.issues = []
      end
    end

    # Stub the render layer and record the locals run wires into each chart's binding. The stubs also
    # assert they receive a real Binding (and the template's own file), so run must pass them through.
    def capture_rendered_charts chart
      captured = []
      allow(chart).to receive(:render_top_text) do |caller_binding|
        raise "render_top_text needs a Binding, got #{caller_binding.class}" unless caller_binding.is_a?(Binding)

        'TOP|'
      end
      allow(chart).to receive(:render) do |caller_binding, file|
        raise 'render needs a Binding' unless caller_binding.is_a?(Binding)
        raise "render needs its own template file, got #{file.inspect}" unless file.to_s.end_with?('sprint_burndown.rb')

        captured << {
          y_axis_title: caller_binding.local_variable_get(:y_axis_title),
          labels: caller_binding.local_variable_get(:data_sets).collect { |ds| ds[:label] },
          legend: caller_binding.local_variable_get(:legend)
        }
        "[#{caller_binding.local_variable_get(:y_axis_title)}]"
      end
      captured
    end

    it 'returns nil when the board is not a scrum board' do
      sprint_burndown.options = :points_and_counts
      expect(sprint_burndown.run).to be_nil
    end

    it 'renders one chart per enabled measure, wiring the sprint data and the matching legend' do
      captured = capture_rendered_charts scrum_chart
      scrum_chart.options = :points_and_counts
      result = scrum_chart.run
      aggregate_failures do
        expect(result).to eq 'TOP|[Story Points][Story Count]'
        expect(captured.collect { |c| c[:y_axis_title] }).to eq ['Story Points', 'Story Count']
        expect(captured.collect { |c| c[:labels] }).to eq [['Sprint One'], ['Sprint One']]
        expect(captured[0][:legend].first).to eq(
          '<b>Started</b>: Total count of story points when the sprint was started'
        )
        expect(captured[1][:legend].first).to eq(
          '<b>Started</b>: Number of issues already in the sprint, when the sprint was started.'
        )
      end
    end

    it 'renders only the story-points chart for points_only' do
      captured = capture_rendered_charts scrum_chart
      scrum_chart.options = :points_only
      scrum_chart.run
      expect(captured.collect { |c| c[:y_axis_title] }).to eq ['Story Points']
    end

    it 'renders only the story-count chart for counts_only' do
      captured = capture_rendered_charts scrum_chart
      scrum_chart.options = :counts_only
      scrum_chart.run
      expect(captured.collect { |c| c[:y_axis_title] }).to eq ['Story Count']
    end
  end

  describe '#sprints_in_time_range' do
    # time_range is deliberately narrow so we can place sprints on either side of both edges.
    let(:range_chart) do
      described_class.new.tap do |chart|
        chart.time_range = to_time('2022-03-01')..to_time('2022-03-31T23:59:59 +00:00')
      end
    end

    def make_sprint id:, state:, start: nil, ending: nil, completed: nil
      raw = { 'id' => id, 'state' => state, 'name' => "S#{id}" }
      raw['activatedDate'] = start if start
      raw['endDate'] = ending if ending
      raw['completeDate'] = completed if completed
      Sprint.new(raw: raw, timezone_offset: '+00:00')
    end

    it 'keeps only started sprints whose active span overlaps the time range' do
      in_range = make_sprint(id: 1, state: 'active', start: '2022-03-10', ending: '2022-03-20')
      starts_in = make_sprint(id: 2, state: 'active', start: '2022-03-25', ending: '2022-04-30')
      ends_in = make_sprint(id: 3, state: 'closed', start: '2022-01-01', ending: '2022-03-05', completed: '2022-03-05')
      spans = make_sprint(id: 4, state: 'active', start: '2022-02-01', ending: '2022-04-30')
      before = make_sprint(id: 5, state: 'closed', start: '2022-01-01', ending: '2022-01-31', completed: '2022-01-31')
      after = make_sprint(id: 6, state: 'active', start: '2022-05-01', ending: '2022-05-31')
      future = make_sprint(id: 7, state: 'future', start: '2022-03-10', ending: '2022-03-20')
      never_started = make_sprint(id: 8, state: 'active', ending: '2022-03-15')
      # completed_time (out of range) must win over end_time (in range), so this one is excluded.
      completed_out = make_sprint(
        id: 9, state: 'closed', start: '2022-01-01', ending: '2022-03-15', completed: '2022-02-01'
      )

      board = instance_double(Board, sprints: [
        in_range, starts_in, ends_in, spans, before, after, future, never_started, completed_out
      ])
      expect(range_chart.sprints_in_time_range(board)).to eq [in_range, starts_in, ends_in, spans]
    end
  end

  describe '#gather_change_data_by_sprint' do
    it 'collects and time-sorts each sprint\'s changes across all issues' do
      issue_a = load_issue('SP-1', board: board).tap { |issue| issue.changes.clear }
      issue_b = load_issue('SP-2', board: board).tap { |issue| issue.changes.clear }
      board.cycletime = mock_cycletime_config stub_values: [
        [issue_a, '2022-01-01', nil], [issue_b, '2022-01-01', nil]
      ]
      # issue_b enters before issue_a even though issue_a is listed first, so the sort matters.
      add_mock_change(issue: issue_b, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-03-05')
      add_mock_change(issue: issue_a, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-03-10')
      sprint_burndown.issues = [issue_a, issue_b]

      result = sprint_burndown.gather_change_data_by_sprint([sprint])
      aggregate_failures do
        expect(result.keys).to eq [sprint]
        expect(result[sprint].collect { |change| [change.issue.key, change.time] }).to eq [
          ['SP-2', to_time('2022-03-05')],
          ['SP-1', to_time('2022-03-10')]
        ]
      end
    end
  end

  describe '#legend_for' do
    it 'lists the story-points legend' do
      expect(sprint_burndown.legend_for(:data_set_by_story_points)).to eq [
        '<b>Started</b>: Total count of story points when the sprint was started',
        '<b>Completed</b>: Count of story points completed during the sprint',
        '<b>Added</b>: Count of story points added in the middle of the sprint',
        '<b>Removed</b>: Count of story points removed while the sprint was in progress'
      ]
    end

    it 'lists the story-counts legend' do
      expect(sprint_burndown.legend_for(:data_set_by_story_counts)).to eq [
        '<b>Started</b>: Number of issues already in the sprint, when the sprint was started.',
        '<b>Completed</b>: Number of issues, completed during the sprint',
        '<b>Added</b>: Number of issues added in the middle of the sprint',
        '<b>Removed</b>: Number of issues removed while the sprint was in progress'
      ]
    end

    it 'raises for an unknown measure' do
      expect { sprint_burndown.legend_for(:bogus) }.to raise_error 'Unexpected method bogus'
    end
  end

  describe '#sprint_data_sets' do
    def named_sprint id, name
      Sprint.new(
        raw: {
          'id' => id, 'state' => 'active', 'name' => name,
          'activatedDate' => '2022-03-05T00:00:00z', 'endDate' => '2022-03-20T00:00:00z'
        },
        timezone_offset: '+00:00'
      )
    end

    it 'builds one data set per sprint, each in its own palette colour, wiring that sprint\'s data' do
      first = named_sprint 1, 'First'
      second = named_sprint 2, 'Second'
      # Echo both the sprint and its change data back so we prove each sprint reaches its own builder
      # call with its own data (a dropped sprint argument would blow up on sprint.name).
      allow(sprint_burndown).to receive(:data_set_by_story_points) do |sprint:, change_data_for_sprint:|
        [sprint.name, *change_data_for_sprint]
      end

      result = sprint_burndown.sprint_data_sets(
        data_method: :data_set_by_story_points,
        sprints: [first, second],
        change_data_by_sprint: { first => [:first_data], second => [:second_data] }
      )
      expect(result).to eq [
        {
          label: 'First', data: ['First', :first_data], fill: false, showLine: true,
          borderColor: CssVariable['--sprint-burndown-sprint-color-1'],
          backgroundColor: CssVariable['--sprint-burndown-sprint-color-1'],
          stepped: true, pointStyle: %w[rect circle]
        },
        {
          label: 'Second', data: ['Second', :second_data], fill: false, showLine: true,
          borderColor: CssVariable['--sprint-burndown-sprint-color-2'],
          backgroundColor: CssVariable['--sprint-burndown-sprint-color-2'],
          stepped: true, pointStyle: %w[rect circle]
        }
      ]
    end

    it 'cycles through the palette and wraps back to the first colour once it runs past the end' do
      palette_size = ChartBase::OKABE_ITO_PALETTE.size
      # One more sprint than the palette has colours, so the last sprint must wrap around.
      sprints = (0..palette_size).collect { |i| named_sprint(i + 1, "S#{i}") }
      allow(sprint_burndown).to receive(:data_set_by_story_points).and_return([])

      colours = sprint_burndown.sprint_data_sets(
        data_method: :data_set_by_story_points, sprints: sprints, change_data_by_sprint: {}
      ).collect { |data_set| data_set[:borderColor] }

      aggregate_failures do
        # The final palette slot really is used (guards the inclusive range)...
        expect(colours[palette_size - 1]).to eq CssVariable["--sprint-burndown-sprint-color-#{palette_size}"]
        # ...and the sprint past the end wraps back to the first colour (guards the modulo).
        expect(colours[palette_size]).to eq CssVariable['--sprint-burndown-sprint-color-1']
      end
    end
  end

  describe '#changes_for_one_issue' do
    let(:issue) { load_issue('SP-1', board: board).tap { |issue| issue.changes.clear } }

    it 'returns empty list for no changes' do
      board.cycletime = mock_cycletime_config stub_values: []
      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint)).to be_empty
    end

    it 'returns start and end only' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-02-01']
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-03')
      add_mock_change(issue: issue, field: 'Sprint', value: '', value_id: '', time: '2022-01-04')
      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint)).to eql [
        SprintIssueChangeData.new(
          action: :enter_sprint, time: to_time('2022-01-03'), value: 0.0, issue: issue, estimate: 0.0
        ),
        SprintIssueChangeData.new(
          action: :leave_sprint, time: to_time('2022-01-04'), value: 0.0, issue: issue, estimate: 0.0
        )
      ]
    end

    it 'changes points at various times for item that was in sprint from the beginning' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-01-05']
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      add_mock_change(issue: issue, field: 'Story Points', value: 2.0, old_value: nil, time: '2022-01-02')
      sprint.raw['activatedDate'] = '2021-01-03'
      add_mock_change(issue: issue, field: 'Story Points', value: 4.0, old_value: 2.0, time: '2022-01-04')
      # Issue closes on Jan 5
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 10_002, time: '2022-01-05')
      add_mock_change(issue: issue, field: 'Story Points', value: '6.0', time: '2022-01-06')

      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint)).to eql [
        SprintIssueChangeData.new(
          action: :enter_sprint, time: to_time('2022-01-01'), value: 0.0, issue: issue, estimate: 0.0
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: to_time('2022-01-02'), value: 2.0, issue: issue, estimate: 2.0
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: to_time('2022-01-04'), value: 2.0, issue: issue, estimate: 4.0
        ),
        SprintIssueChangeData.new(
          action: :issue_stopped, time: to_time('2022-01-05'), value: -4.0, issue: issue, estimate: 4.0
        )
      ]
    end

    it 'counts estimate changes for an issue that never completed' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', nil] # started, never stopped -> no completion time
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      add_mock_change(issue: issue, field: 'Story Points', value: 3.0, old_value: nil, time: '2022-01-02')

      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint)).to eql [
        SprintIssueChangeData.new(
          action: :enter_sprint, time: to_time('2022-01-01'), value: 0.0, issue: issue, estimate: 0.0
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: to_time('2022-01-02'), value: 3.0, issue: issue, estimate: 3.0
        )
      ]
    end

    it 'ignores field changes that are neither the sprint nor the estimate' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', nil]
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      add_mock_change(issue: issue, field: 'priority', value: 'High', old_value: 'Low', time: '2022-01-02')

      # Only the sprint entry survives; the priority change is not an estimate change.
      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint).map(&:action)).to eq [:enter_sprint]
    end

    it 'records issue_stopped only once when several changes land on the completion time' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-01-05']
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 10_002, time: '2022-01-05')
      add_mock_change(issue: issue, field: 'resolution', value: 'Fixed', time: '2022-01-05')

      actions = sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint).map(&:action)
      expect(actions).to eq %i[enter_sprint issue_stopped]
    end

    it 'does not re-enter the sprint when a redundant sprint change repeats it' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', nil]
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-02')

      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint).map(&:action)).to eq [:enter_sprint]
    end

    it 'returns empty when the issue is never in the sprint, even if it has other changes' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-01-05']
      ]
      add_mock_change(issue: issue, field: 'Story Points', value: 3.0, old_value: nil, time: '2022-01-02')

      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint)).to be_empty
    end

    it 'tracks fractional points (from string values), skips irrelevant changes, and leaves with a negative value' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', nil]
      ]
      # Jira sends change values as strings; the estimate and the delta from the old value are numeric.
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      add_mock_change(issue: issue, field: 'Story Points', value: '2.5', old_value: nil, time: '2022-01-02')
      add_mock_change(issue: issue, field: 'Story Points', value: '4.0', old_value: '2.5', time: '2022-01-03')
      add_mock_change(issue: issue, field: 'priority', value: 'High', old_value: 'Low', time: '2022-01-04')
      add_mock_change(issue: issue, field: 'Sprint', value: '', value_id: '', time: '2022-01-05')

      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint)).to eql [
        SprintIssueChangeData.new(
          action: :enter_sprint, time: to_time('2022-01-01'), value: 0.0, issue: issue, estimate: 0.0
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: to_time('2022-01-02'), value: 2.5, issue: issue, estimate: 2.5
        ),
        SprintIssueChangeData.new(
          action: :story_points, time: to_time('2022-01-03'), value: 1.5, issue: issue, estimate: 4.0
        ),
        SprintIssueChangeData.new(
          action: :leave_sprint, time: to_time('2022-01-05'), value: -4.0, issue: issue, estimate: 4.0
        )
      ]
    end

    it 'marks issue_stopped only at the completion time, not at an earlier change' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', '2022-01-05']
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      add_mock_change(issue: issue, field: 'priority', value: 'High', old_value: 'Low', time: '2022-01-03')
      add_mock_change(issue: issue, field: 'status', value: 'Done', value_id: 10_002, time: '2022-01-05')

      actions = sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint).map { |c| [c.action, c.time] }
      expect(actions).to eq [[:enter_sprint, to_time('2022-01-01')], [:issue_stopped, to_time('2022-01-05')]]
    end

    it 'only enters when the sprint change is actually for this sprint' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', nil]
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: 'Other', value_id: '999', time: '2022-01-01')
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-02')

      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint).map { |c| [c.action, c.time] })
        .to eq [[:enter_sprint, to_time('2022-01-02')]]
    end

    it 'does not leave again once it is already out of the sprint' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2022-01-01', nil]
      ]
      add_mock_change(issue: issue, field: 'Sprint', value: sprint.name, value_id: sprint.id.to_s, time: '2022-01-01')
      add_mock_change(issue: issue, field: 'Sprint', value: '', value_id: '', time: '2022-01-02')
      add_mock_change(issue: issue, field: 'Sprint', value: 'Other', value_id: '999', time: '2022-01-03')

      expect(sprint_burndown.changes_for_one_issue(issue: issue, sprint: sprint).map(&:action))
        .to eq %i[enter_sprint leave_sprint]
    end
  end

  describe '#data_set_by_story_points' do
    let(:issue1) { load_issue('SP-1').tap { |issue| issue.changes.clear } }
    let(:issue2) { load_issue('SP-2').tap { |issue| issue.changes.clear } }

    it 'handles an empty active sprint' do
      change_data = []
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 0.0, title: 'Sprint started with 0.0 points' },
          { x: '2022-04-11T23:59:59+0000', y: 0.0, title: 'Sprint still active. 0.0 points still in progress.' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 0.0, added: 0, removed: 0, completed: 0.0, remaining: 0, points_values_changed: false
        )
      end
    end

    it 'handles an empty completed sprint' do
      change_data = []
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 0.0, title: 'Sprint started with 0.0 points' },
          { x: '2022-04-10T00:00:00+0000', y: 0.0, title: 'Sprint ended with 0.0 points unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 0.0, added: 0, removed: 0, completed: 0.0, remaining: 0.0, points_values_changed: false
        )
      end
    end

    it 'handles complex case with active sprint' do
      change_data = [
        # Sprint start is 2022-03-26

        SprintIssueChangeData.new( # Has points assigned but not in sprint at start
          time: to_time('2022-03-23'), action: :story_points, value: 2.0, issue: issue2, estimate: 2.0
        ),

        SprintIssueChangeData.new(
          time: to_time('2022-03-23'), action: :story_points, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :story_points, value: 7.0, issue: issue1, estimate: 12.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 12.0
        ),

        # sprint starts here

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :story_points, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new( # Should be ignored because it's in sprint yet
          time: to_time('2022-03-27'), action: :story_points, value: 2.0, issue: issue2, estimate: 4.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :enter_sprint, value: nil, issue: issue2, estimate: 4.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 12.0, title: 'Sprint started with 12.0 points' },
          { x: '2022-03-27T00:00:00+0000', y: 17.0, title: 'SP-1 Story points changed from 0.0 points to 5.0 points' },
          { x: '2022-03-28T00:00:00+0000', y: 21.0, title: 'SP-2 Added to sprint with 4.0 points' },
          { x: '2022-04-11T23:59:59+0000', y: 21.0, title: 'Sprint still active. 21.0 points still in progress.' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 12.0, added: 4.0, removed: 0, completed: 0.0, remaining: 0, points_values_changed: true
        )
      end
    end

    it 'ignores changes after sprint end' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-23'), action: :story_points, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 5.0
        ),

        # sprint starts and then ends here

        SprintIssueChangeData.new(
          time: to_time('2022-04-11'), action: :story_points, value: -2.0, issue: issue1, estimate: 3.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 5.0, title: 'Sprint started with 5.0 points' },
          { x: '2022-04-10T00:00:00+0000', y: 5.0, title: 'Sprint ended with 5.0 points unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 5.0, added: 0, removed: 0, completed: 0.0, remaining: 5.0, points_values_changed: false
        )
      end
    end

    it 'handles an issue being removed mid-sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, estimate: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :leave_sprint, value: -5.0, issue: issue1, estimate: 5.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 12.0, title: 'Sprint started with 12.0 points' },
          { x: '2022-03-27T00:00:00+0000', y: 7.0, title: 'SP-1 Removed from sprint with 5.0 points' },
          { x: '2022-04-10T00:00:00+0000', y: 7.0, title: 'Sprint ended with 7.0 points unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 12.0, added: 0, removed: 5.0, completed: 0.0, remaining: 7.0, points_values_changed: false
        )
      end
    end

    it 'handles an issue being completed mid-sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, estimate: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :issue_stopped, value: -5.0, issue: issue1, estimate: 5.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 12.0, title: 'Sprint started with 12.0 points' },
          { x: '2022-03-27T00:00:00+0000', y: 7.0, title: 'SP-1 Completed with 5.0 points' },
          { x: '2022-04-10T00:00:00+0000', y: 7.0, title: 'Sprint ended with 7.0 points unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 12.0, added: 0, removed: 0, completed: 5.0, remaining: 7.0, points_values_changed: false
        )
      end
    end

    it 'handles an issue with zero points being completed mid-sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 0.0, issue: issue1, estimate: 0.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, estimate: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :issue_stopped, value: 0.0, issue: issue1, estimate: 0.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 7.0, title: 'Sprint started with 7.0 points' },
          { x: '2022-03-27T00:00:00+0000', y: 7.0, title: 'SP-1 Completed with 0.0 points' },
          { x: '2022-04-10T00:00:00+0000', y: 7.0, title: 'Sprint ended with 7.0 points unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 7.0, added: 0, removed: 0, completed: 0.0, remaining: 7.0, points_values_changed: false
        )
      end
    end

    it 'includes a change that lands exactly on the sprint start time' do
      change_data = [
        SprintIssueChangeData.new(
          time: to_time('2022-03-26T00:00:00'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 5.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 0.0, title: 'Sprint started with 0.0 points' },
          { x: '2022-03-26T00:00:00+0000', y: 5.0, title: 'SP-1 Added to sprint with 5.0 points' },
          { x: '2022-04-11T23:59:59+0000', y: 5.0, title: 'Sprint still active. 5.0 points still in progress.' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 0.0, added: 5.0, removed: 0, completed: 0.0, remaining: 0, points_values_changed: false
        )
      end
    end

    it 'ignores story point changes for an issue after it has completed' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :issue_stopped, value: -5.0, issue: issue1, estimate: 5.0
        ),
        # SP-1 is no longer in the sprint, so this later points change must be ignored.
        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :story_points, value: 3.0, issue: issue1, estimate: 8.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 5.0, title: 'Sprint started with 5.0 points' },
          { x: '2022-03-27T00:00:00+0000', y: 0.0, title: 'SP-1 Completed with 5.0 points' },
          { x: '2022-04-10T00:00:00+0000', y: 0.0, title: 'Sprint ended with 0.0 points unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 5.0, added: 0, removed: 0, completed: 5.0, remaining: 0.0, points_values_changed: false
        )
      end
    end

    it 'ignores story point changes for an issue after it has been removed from the sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :leave_sprint, value: -5.0, issue: issue1, estimate: 5.0
        ),
        # SP-1 is no longer in the sprint, so this later points change must be ignored.
        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :story_points, value: 3.0, issue: issue1, estimate: 8.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 5.0, title: 'Sprint started with 5.0 points' },
          { x: '2022-03-27T00:00:00+0000', y: 0.0, title: 'SP-1 Removed from sprint with 5.0 points' },
          { x: '2022-04-10T00:00:00+0000', y: 0.0, title: 'Sprint ended with 0.0 points unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 5.0, added: 0, removed: 5.0, completed: 0.0, remaining: 0.0, points_values_changed: false
        )
      end
    end

    it 'records the starting total when every change predates the sprint start' do
      change_data = [
        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, estimate: 7.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 12.0, title: 'Sprint started with 12.0 points' },
          { x: '2022-04-11T23:59:59+0000', y: 12.0, title: 'Sprint still active. 12.0 points still in progress.' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 12.0, added: 0, removed: 0, completed: 0.0, remaining: 0, points_values_changed: false
        )
      end
    end

    it 'raises error if an illegal action is passed in' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :illegal_action, value: 0.0, issue: issue1, estimate: 0.0
        )
      ]
      expect { sprint_burndown.data_set_by_story_points(change_data_for_sprint: change_data, sprint: sprint) }.to(
        raise_error 'Unexpected action: illegal_action'
      )
    end
  end

  describe '#data_set_by_story_counts' do
    let(:issue1) { load_issue('SP-1').tap { |issue| issue.changes.clear } }
    let(:issue2) { load_issue('SP-2').tap { |issue| issue.changes.clear } }

    it 'handles an empty active sprint' do
      change_data = []
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 0, title: 'Sprint started with 0 stories' },
          { x: '2022-04-11T23:59:59+0000', y: 0, title: 'Sprint still active. 0 issues in progress.' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 0, added: 0, removed: 0, completed: 0, remaining: 0, points_values_changed: false
        )
      end
    end

    it 'handles an empty completed sprint' do
      change_data = []
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 0, title: 'Sprint started with 0 stories' },
          { x: '2022-04-10T00:00:00+0000', y: 0, title: 'Sprint ended with 0 stories unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 0, added: 0, removed: 0, completed: 0, remaining: 0, points_values_changed: false
        )
      end
    end

    it 'handles complex case with active sprint' do
      change_data = [
        # Sprint start is 2022-03-26

        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 12.0
        ),

        # sprint starts here

        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :enter_sprint, value: nil, issue: issue2, estimate: 4.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 1.0, title: 'Sprint started with 1 stories' },
          { x: '2022-03-28T00:00:00+0000', y: 2.0, title: 'SP-2 Added to sprint' },
          { x: '2022-04-11T23:59:59+0000', y: 2.0, title: 'Sprint still active. 2 issues in progress.' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 1, added: 1, removed: 0, completed: 0, remaining: 0, points_values_changed: false
        )
      end
    end

    it 'handles an issue being removed mid-sprint' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: nil, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: nil, issue: issue2, estimate: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new(
          time: to_time('2022-03-27'), action: :leave_sprint, value: nil, issue: issue1, estimate: 5.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 2, title: 'Sprint started with 2 stories' },
          { x: '2022-03-27T00:00:00+0000', y: 1, title: 'SP-1 Removed from sprint' },
          { x: '2022-04-10T00:00:00+0000', y: 1, title: 'Sprint ended with 1 stories unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 2, added: 0, removed: 1, completed: 0, remaining: 1, points_values_changed: false
        )
      end
    end

    it 'handles an issue being completed mid-sprint and should ignore one after sprint end' do
      sprint.raw['completeDate'] = '2022-04-10T00:00:00z'
      change_data = [
        # Sprint start is 2022-03-26, end is 2022-04-10

        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: 5.0, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: 7.0, issue: issue2, estimate: 7.0
        ),

        # sprint starts

        SprintIssueChangeData.new( # This should be ignored
          time: to_time('2022-03-27'), action: :story_points, value: 4.0, issue: issue1, estimate: 9.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-28'), action: :issue_stopped, value: -5.0, issue: issue1, estimate: 5.0
        ),

        # sprint ends

        SprintIssueChangeData.new(
          time: to_time('2022-04-11'), action: :issue_stopped, value: -7.0, issue: issue1, estimate: 7.0
        )

      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 2, title: 'Sprint started with 2 stories' },
          { x: '2022-03-28T00:00:00+0000', y: 1, title: 'SP-1 Completed' },
          { x: '2022-04-10T00:00:00+0000', y: 1, title: 'Sprint ended with 1 stories unfinished' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 2, added: 0, removed: 0, completed: 1, remaining: 1, points_values_changed: false
        )
      end
    end

    it 'includes a change that lands exactly on the sprint start time' do
      change_data = [
        SprintIssueChangeData.new(
          time: to_time('2022-03-26T00:00:00'), action: :enter_sprint, value: nil, issue: issue1, estimate: 5.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 0, title: 'Sprint started with 0 stories' },
          { x: '2022-03-26T00:00:00+0000', y: 1, title: 'SP-1 Added to sprint' },
          { x: '2022-04-11T23:59:59+0000', y: 1, title: 'Sprint still active. 1 issues in progress.' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 0, added: 1, removed: 0, completed: 0, remaining: 0, points_values_changed: false
        )
      end
    end

    it 'records the starting count when every change predates the sprint start' do
      change_data = [
        SprintIssueChangeData.new(
          time: to_time('2022-03-24'), action: :enter_sprint, value: nil, issue: issue1, estimate: 5.0
        ),
        SprintIssueChangeData.new(
          time: to_time('2022-03-25'), action: :enter_sprint, value: nil, issue: issue2, estimate: 7.0
        )
      ]
      aggregate_failures do
        expect(sprint_burndown.data_set_by_story_counts(change_data_for_sprint: change_data, sprint: sprint)).to eq [
          { x: '2022-03-26T00:00:00+0000', y: 2, title: 'Sprint started with 2 stories' },
          { x: '2022-04-11T23:59:59+0000', y: 2, title: 'Sprint still active. 2 issues in progress.' }
        ]
        expect(sprint_burndown.summary_stats[sprint]).to have_attributes(
          started: 2, added: 0, removed: 0, completed: 0, remaining: 0, points_values_changed: false
        )
      end
    end
  end
end
