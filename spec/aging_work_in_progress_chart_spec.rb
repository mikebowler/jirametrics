# frozen_string_literal: true

require './spec/spec_helper'

def complete_sample_board_columns
  json = JSON.parse(file_system.load('./spec/complete_sample/sample_board_1_configuration.json'))
  json['columnConfig']['columns'].collect { |raw| BoardColumn.new raw }
end

describe AgingWorkInProgressChart do
  let(:today) { to_date('2021-06-28') }

  let(:board) do
    load_complete_sample_board.tap do |board|
      # block = lambda do |_|
      #   start_at first_time_in_status_category :indeterminate
      #   stop_at first_time_in_status_category :done
      # end
      # board.cycletime = CycleTimeConfig.new(
      #   parent_config: nil, label: 'test', file_system: nil, today: today, block: block
      # )
      board.cycletime = default_cycletime_config
    end
  end

  let :chart do
    chart = described_class.new(empty_config_block)
    chart.file_system = MockFileSystem.new
    chart.board_id = 1
    chart.all_boards = { 1 => board }
    chart.issues = load_complete_sample_issues board: board

    # None of the sample issues are complete so we need to add one complete item in order for the 85% line to work.
    chart.issues << create_issue_from_aging_data(
      board: board, ages_by_column: [1, 2, 3, 7], today: today.to_s, key: 'SP-100'
    )
    chart.issues.last.changes << mock_change(field: 'resolution', time: to_time(today.to_s), value: 'done')

    chart.date_range = to_date('2021-06-18')..today
    chart.percentiles 85 => '--aging-work-in-progress-chart-shading-color'
    chart.show_all_columns
    chart
  end

  context 'column_for' do
    it 'returns name' do
      chart.run

      # The last issue is the fake 'done' that we inserted so look at the one before that.
      actual = chart.column_for(issue: chart.issues[-2]).name
      expect(actual).to eq 'Review'
    end
  end

  it 'make_data_sets' do
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
       'data' => [1, 2, 4, 10],
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

  context 'indexes_of_leading_and_trailing_zeros' do
    it 'handles empty' do
      expect(chart.indexes_of_leading_and_trailing_zeros []).to be_empty
    end

    it 'handles all zeros' do
      expect(chart.indexes_of_leading_and_trailing_zeros [0, 0]).to eq [0, 1]
    end

    it 'handles leading and trailing zeros' do
      expect(chart.indexes_of_leading_and_trailing_zeros [0, 0, 5, 0]).to eq [0, 1, 3]
    end

    it 'handles no zeros' do
      expect(chart.indexes_of_leading_and_trailing_zeros [5, 5, 5]).to be_empty
    end

    it 'ignore zero in the middle' do
      expect(chart.indexes_of_leading_and_trailing_zeros [2, 0, 5, 0]).to eq [3]
    end
  end

  context 'adjust_bar_data' do
    it 'returns empty for empty' do
      expect(chart.adjust_bar_data []).to be_empty
    end

    it 'accumulates' do
      input = [
        [2, 4, 2, 0],
        [4, 3, 5, 0],
        [8, 7, 8, 0],
        [6, 8, 6, 0]
      ]

      expect(chart.adjust_bar_data input).to eq [
        [ 2,  4,  2, 0], # rubocop:disable Layout/SpaceInsideArrayLiteralBrackets
        [ 6,  7,  7, 0], # rubocop:disable Layout/SpaceInsideArrayLiteralBrackets
        [14, 14, 15, 0],
        [20, 22, 21, 0]
      ]
    end
  end
end
