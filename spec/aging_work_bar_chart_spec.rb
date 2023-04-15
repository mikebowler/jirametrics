# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkBarChart do
  let(:subject) { AgingWorkBarChart.new }

  context 'data_set_by_block' do
    it 'should handle nothing blocked at all' do
      issue = load_issue('SP-1')
      data_sets = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| false }

      expect(data_sets).to eq({
        backgroundColor: 'red',
        data: [],
        stack: 'blocked',
        stacked: true,
        type: 'bar'
      })
    end

    it 'should handle a single blocked range completely within the date range' do
      issue = load_issue('SP-1')
      data_sets = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..6).include? day.day }

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

    it 'should handle multiple blocked ranges, all completely within the date range' do
      issue = load_issue('SP-1')
      data_set = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..4).include?(day.day) || day.day == 6 }

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
      issue = load_issue('SP-1')
      data_set = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| true }

      # Only checking the data section as the full wrapper was tested above.
      expect(data_set[:data]).to eq([
        {
          title: 'Story : Blocked 10 days',
          x: %w[2022-01-01 2022-01-10],
          y: 'SP-1'
        }
      ])
    end
  end

  context 'status_data_sets' do
    it 'should return nil if no status' do
      subject.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      subject.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config(stub_values: [[issue, '2021-01-01', nil]])
      data_sets = subject.status_data_sets(
        issue: issue, label: issue.key, today: to_date('2021-01-05')
      )
      expect(data_sets).to eq([
        {
          backgroundColor: 'gray',
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

    it 'should handle blocked by flag' do
      subject.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      subject.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(field: 'Flagged', value: 'Flagged', time: '2021-01-02T01:00:00')
      issue.changes << mock_change(field: 'Flagged', value: '',        time: '2021-01-02T02:00:00')

      data_sets = subject.blocked_data_sets issue: issue, stack: 'blocked', color: 'pink', issue_label: 'SP-1'
      expect(data_sets).to eq([
        {
          backgroundColor: 'pink',
          data: [
            {
              title: 'Flagged',
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

    it 'should handle blocked by status' do
      board.project_config.settings['blocked_statuses'] = ['Blocked']
      subject.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      subject.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(field: 'status', value: 'Blocked', time: '2021-01-02')
      issue.changes << mock_change(field: 'status', value: 'Doing',   time: '2021-01-03')

      data_sets = subject.blocked_data_sets issue: issue, stack: 'blocked', color: 'pink', issue_label: 'SP-1'
      expect(data_sets).to eq([
        {
          backgroundColor: 'pink',
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

    it 'should handle blocked by issue' do
      board.project_config.settings['blocked_link_text'] = ['is blocked by']

      subject.date_range = to_date('2021-01-01')..to_date('2021-01-05')
      subject.timezone_offset = '+0000'
      issue = empty_issue created: '2021-01-01', board: board
      issue.changes << mock_change(
        field: 'Link', value: 'This issue is blocked by SP-10', time: '2021-01-02'
      )
      issue.changes << mock_change(
        field: 'Link', value: nil, old_value: 'This issue is blocked by SP-10', time: '2021-01-03'
      )

      data_sets = subject.blocked_data_sets issue: issue, stack: 'blocked', color: 'pink', issue_label: 'SP-1'
      expect(data_sets).to eq([
        {
          backgroundColor: 'pink',
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

    # TODO: Test stalled
    # TODO: Test a complex case with all of the above.
  end
end
