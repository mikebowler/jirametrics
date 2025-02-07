# frozen_string_literal: true

require './spec/spec_helper'

def complete_sample_board_columns
  json = JSON.parse(file_system.load('./spec/complete_sample/sample_board_1_configuration.json'))
  json['columnConfig']['columns'].collect { |raw| BoardColumn.new raw }
end

describe AgingWorkInProgressChart do
  let(:board) { load_complete_sample_board }
  let :chart do
    chart = described_class.new(empty_config_block)
    chart.file_system = MockFileSystem.new
    chart.board_id = 1
    chart.all_boards = { 1 => board }
    board.cycletime = default_cycletime_config
    chart.issues = load_complete_sample_issues board: board
    chart.date_range = Date.parse('2021-06-18')..Date.parse('2021-06-28')
    chart
  end

  context 'column_for' do
    it 'returns name' do
      chart.run

      actual = chart.column_for(issue: chart.issues[-1]).name
      expect(actual).to eq 'Review'
    end
  end

  it 'make _data_sets' do
    chart.run

    expect(chart.make_data_sets).to eq([
      {
        'backgroundColor' => CssVariable['--type-story-color'],
        'data' => [
          {
            'title' => ['SP-11 : Report of all orders for an event (11 days)'],
            'x' => 'Ready',
            'y' => 11
          },
          {
            'title' => ['SP-8 : Refund ticket for individual order (11 days)'],
             'x' => 'In Progress',
             'y' => 11
          },
          {
            'title' => ['SP-7 : Purchase ticket with Apple Pay (11 days)'],
             'x' => 'Ready',
             'y' => 11
          },
          {
            'title' => ['SP-2 : Update existing event (11 days)'],
             'x' => 'Ready',
             'y' => 11
          },
          {
            'title' => ['SP-1 : Create new draft event (11 days)'],
            'x' => 'Review',
            'y' => 11
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
       'backgroundColor' => CssVariable['--aging-work-in-progress-chart-shading-color'],
       'type' => 'bar'
     }
    ])
  end

  context 'Extra column for unmapped statuses' do
    it 'shows the column when an issue is present with that status' do
      chart.time_range = to_time('2021-10-01')..to_time('2021-10-30')
      issue = empty_issue created: '2021-10-01', board: board
      issue.raw['fields']['status'] = {
        'name' => 'FakeBacklog',
        'id' => '10012',
        'statusCategory' => {
          'name' => 'To Do',
          'id' => '2',
          'key' => 'new'
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

    it 'hides the column when no issues are in that status' do
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
