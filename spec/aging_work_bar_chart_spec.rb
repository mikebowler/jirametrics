# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkBarChart do
  let(:chart) { described_class.new(empty_config_block) }
  let(:board) { sample_board }
  let(:issue1) { load_issue('SP-1', board: board) }
  let(:issue2) { load_issue('SP-2', board: board) }

  context 'data_set_by_block' do
    it 'handles nothing blocked at all' do
      data_sets = chart.data_set_by_block(
        issue: issue1, issue_label: issue1.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| false }

      expect(data_sets).to be_empty
    end

    it 'handles a single blocked range completely within the date range' do
      data_sets = chart.data_set_by_block(
        issue: issue1, issue_label: issue1.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..6).cover? day.day }

      expect(data_sets).to eq(
        {
          backgroundColor: 'red',
          data: [
            {
              title: 'Story : Blocked 4 days',
              x: %w[2022-01-03 2022-01-06],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      )
    end

    it 'handles multiple blocked ranges, all completely within the date range' do
      data_set = chart.data_set_by_block(
        issue: issue1, issue_label: issue1.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..4).cover?(day.day) || day.day == 6 }

      # Only checking the data section as the full wrapper was tested above.
      expect(data_set[:data]).to eq([
        {
          title: 'Story : Blocked 2 days',
          x: %w[2022-01-03 2022-01-04],
          y: 'SP-1'
        },
        {
          title: 'Story : Blocked 1 day',
          x: %w[2022-01-06 2022-01-06],
          y: 'SP-1'
        }
      ])
    end

    it 'never becomes unblocked' do
      data_set = chart.data_set_by_block(
        issue: issue1, issue_label: issue1.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| true }

      # Only checking the data section as the full wrapper was tested above.
      expect(data_set).to eq({
        backgroundColor: 'red',
        data: [
          {
            title: 'Story : Blocked 10 days',
            x: %w[2022-01-01 2022-01-10],
            y: 'SP-1'
          }
        ],
        stack: 'blocked',
        stacked: true,
        type: 'bar'
      })
    end
  end

  context 'status_data_sets' do
    it 'returns nil if no status' do
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config(stub_values: [[issue, '2021-01-01', nil]])
      data_sets = chart.status_data_sets(
        issue: issue, label: issue.key, today: to_date('2021-01-05')
      )
      expect(data_sets).to eq([
        {
          backgroundColor: CssVariable['--status-category-todo-color'],
          data: [
            {
              title: 'Bug : Backlog',
              x: ['2021-01-01T00:00:00+0000', '2021-01-05T00:00:00+0000'],
              y: 'SP-1'
            }
          ],
          stack: 'status',
          stacked: true,
          type: 'bar'
        }
      ])
    end
  end

  context 'blocked_data_sets' do
    let(:board) do
      board = sample_board
      board.project_config = ProjectConfig.new(
        exporter: Exporter.new, target_path: 'spec/testdata/', jira_config: nil, block: nil
      )
      board
    end

    it 'handles blocked by flag' do
      chart.settings = board.project_config.settings
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(field: 'Flagged', value: 'Flagged', time: '2021-01-02T01:00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',        time: '2021-01-02T02:00:00')

      data_sets = chart.blocked_data_sets(
        issue: issue, stack: 'blocked', issue_label: 'SP-1', issue_start_time: issue.created
      )
      expect(data_sets).to eq([
        {
          backgroundColor: CssVariable['--blocked-color'],
          data: [
            {
              title: 'Blocked by flag',
              x: ['2021-01-02T01:00:00+0000', '2021-01-02T02:00:00+0000'],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      ])
    end

    it 'handles blocked by status' do
      chart.settings = board.project_config.settings
      chart.settings['blocked_statuses'] = ['Blocked']
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(field: 'status', value: 'Blocked', time: '2021-01-02')
      issue.changes << mock_change(field: 'status', value: 'Doing',   time: '2021-01-03')

      data_sets = chart.blocked_data_sets(
        issue: issue, stack: 'blocked', issue_label: 'SP-1', issue_start_time: issue.created
      )
      expect(data_sets).to eq([
        {
          backgroundColor: CssVariable['--blocked-color'],
          data: [
            {
              title: 'Blocked by status: Blocked',
              x: ['2021-01-02T00:00:00+0000', '2021-01-03T00:00:00+0000'],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      ])
    end

    it 'handle blocked by issue' do
      chart.settings = board.project_config.settings
      chart.settings['blocked_link_text'] = ['is blocked by']

      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = chart.date_range.begin.to_time..chart.date_range.end.to_time
      chart.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(
        field: 'Link', value: 'This issue is blocked by SP-10', time: '2021-01-02'
      )
      issue.changes << mock_change(
        field: 'Link', value: nil, old_value: 'This issue is blocked by SP-10', time: '2021-01-03'
      )

      data_sets = chart.blocked_data_sets(
        issue: issue, stack: 'blocked', issue_label: 'SP-1', issue_start_time: issue.created
      )
      expect(data_sets).to eq([
        {
          backgroundColor: CssVariable['--blocked-color'],
          data: [
            {
              title: 'Blocked by issues: SP-10',
              x: ['2021-01-02T00:00:00+0000', '2021-01-03T00:00:00+0000'],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      ])
    end
  end

  context 'sort_by_age!' do
    it 'leaves an already sorted list alone' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-01', nil],
        [issue2, '2024-01-02', nil]
      ]
      expect(chart.sort_by_age! issues: [issue1, issue2], today: to_date('2024-01-05')).to eq [
        issue1, issue2
      ]
    end

    it 'sorts the list' do
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, '2024-01-02', nil],
        [issue2, '2024-01-01', nil]
      ]
      expect(chart.sort_by_age! issues: [issue1, issue2], today: to_date('2024-01-05')).to eq [
        issue2, issue1
      ]
    end
  end

  context 'select_aging_issues' do
    it 'returns empty when no issues' do
      expect(chart.select_aging_issues issues: []).to be_empty
    end

    it 'selects only aging' do
      issue3 = load_issue 'SP-1', board: board
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, nil, nil],                  # not started
        [issue2, '2024-01-01', nil],         # started
        [issue3, '2024-01-01', '2024-01-05'] # completed
      ]
      expect(chart.select_aging_issues issues: [issue1, issue2, issue3]).to eq [issue2]
    end
  end

  context 'data_sets_for_one_issue' do
    it 'processes issue with no blocked, stalled, or expedited' do
      issue = empty_issue key: 'SP-1', created: '2024-01-01', board: board
      project_config = ProjectConfig.new(exporter: nil, jira_config: nil, block: nil)
      board.project_config = project_config
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2024-01-01', nil]
      ]
      chart.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      chart.time_range = to_time('2021-01-01')..to_time('2021-01-05')
      expect(chart.data_sets_for_one_issue issue: issue, today: to_date('2024-01-10')).to eq [
        [
          {
            backgroundColor: CssVariable['--status-category-todo-color'],
            data: [
              {
                title: 'Bug : Backlog',
                x: ['2024-01-01T00:00:00+0000', '2024-01-10T00:00:00'],
                y: '[10 days] SP-1: '
              }
            ],
            stack: 'status',
            stacked: true,
            type: 'bar'
          }
        ],
        [],
        []
      ]
    end
  end
end
