# frozen_string_literal: true

require './spec/spec_helper'

def complete_sample_board_columns
  json = JSON.parse(File.read('./spec/complete_sample/sample_board_1_configuration.json'))
  json['columnConfig']['columns'].collect { |raw| BoardColumn.new raw }
end

describe AgingWorkInProgressChart do
  let(:board) { load_complete_sample_board }
  let :chart do
    chart = AgingWorkInProgressChart.new
    chart.board_id = 1
    chart.all_boards = { 1 => load_complete_sample_board }
    board.cycletime = default_cycletime_config
    chart.issues = load_complete_sample_issues board: board
    chart
  end

  context 'accumulated_status_ids_per_column' do
    it 'should accumulate properly' do
      chart.issues = load_complete_sample_issues(board: board).select { |issue| board.cycletime.in_progress? issue }
      chart.run

      actual = chart.accumulated_status_ids_per_column
      expect(actual).to eq [
        ['Ready',       [10_002, 10_011, 3, 10_001]],
        ['In Progress', [10_002, 10_011, 3]],
        ['Review',      [10_002, 10_011]],
        ['Done',        [10_002]]
      ]
    end
  end

  context 'ages_of_issues_that_crossed_column_boundary' do
    it 'should handle no issues' do
      issues = []

      actual = chart.ages_of_issues_that_crossed_column_boundary issues: issues, status_ids: [10_002, 10_011]
      expect(actual).to eq []
    end

    it 'should handle no status ids' do
      actual = chart.ages_of_issues_that_crossed_column_boundary issues: chart.issues, status_ids: []
      expect(actual).to eq []
    end

    it 'should handle happy path' do
      actual = chart.ages_of_issues_that_crossed_column_boundary issues: chart.issues, status_ids: [10_002, 10_011, 3]
      expect(actual).to eq [180, 73, 1]
    end
  end

  context 'days_at_percentage_threshold_for_all_columns' do
    it 'at 100%' do
      chart.run

      actual = chart.days_at_percentage_threshold_for_all_columns percentage: 100, issues: chart.issues
      expect(actual).to eq [0, 0, 0, 0]
    end

    it 'at 0%' do
      chart.run
      actual = chart.days_at_percentage_threshold_for_all_columns percentage: 0, issues: chart.issues
      expect(actual).to eq [1, 1, 81, 81]
    end
  end

  context 'column_for' do
    it 'should work' do
      chart.run

      actual = chart.column_for(issue: chart.issues[-1]).name
      expect(actual).to eq 'Review'
    end
  end

  it 'make _data_sets' do
    chart.run

    expect(chart.make_data_sets).to eq([
      {
        'backgroundColor' => 'green',
        'data' => [
          {
            'title' => ['SP-11 : Report of all orders for an event (183 days)'],
            'x' => 'Ready',
            'y' => 183
          },
          {
            'title' => ['SP-8 : Refund ticket for individual order (183 days)'],
             'x' => 'In Progress',
             'y' => 183
          },
          {
            'title' => ['SP-7 : Purchase ticket with Apple Pay (183 days)'],
             'x' => 'Ready',
             'y' => 183
          },
          {
            'title' => ['SP-2 : Update existing event (183 days)'],
             'x' => 'Ready',
             'y' => 183
          },
          {
            'title' => ['SP-1 : Create new draft event (183 days)'],
            'x' => 'Review',
            'y' => 183
          }
        ],
       'fill' => false,
       'label' => 'Story',
       'showLine' => false,
       'type' => 'line'
     },
     {
       'barPercentage' => 1.0,
       'categoryPercentage' => 1.0,
       'data' => [180, 180, 81],
       'label' => '85%',
       'type' => 'bar'
     }
    ])
  end

  context 'Extra column for unmapped statuses' do
    it 'should the column when an issue is present with that status' do
      chart.time_range = to_time('2021-10-01')..to_time('2021-10-30')
      issue = empty_issue created: '2021-10-01', board: board
      issue.raw['fields']['status'] = {
        'name' => 'FakeBacklog',
        'id' => '10012',
        'statusCategory' => {
          'name' => 'To Do',
          'id' => '2'
        }
      }
      board.cycletime = mock_cycletime_config stub_values: [
        [issue, '2021-10-02', nil]
      ]
      chart.issues << issue
      chart.run

      actual = chart.board_columns.collect do |column|
        "#{column.name}: #{column.status_ids.join(',')}"
      end
      expect(actual).to eq [
        'Ready: 10001',
        'In Progress: 3',
        'Review: 10011',
        'Done: 10002',
        '[Unmapped Statuses]: 10000,10012'
      ]
    end

    it 'should hide the column when no issues are in that status' do
      chart.run

      actual = chart.board_columns.collect do |column|
        "#{column.name}: #{column.status_ids.join(',')}"
      end
      expect(actual).to eq [
        'Ready: 10001',
        'In Progress: 3',
        'Review: 10011',
        'Done: 10002'
        # Unmapped status column would be here. Verify it's missing
      ]
    end
  end
end
