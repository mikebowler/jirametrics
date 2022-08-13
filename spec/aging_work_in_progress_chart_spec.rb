# frozen_string_literal: true

require './spec/spec_helper'

def complete_sample_board_columns
  json = JSON.parse(File.read('./spec/complete_sample/sample_board_1_configuration.json'))
  json['columnConfig']['columns'].collect { |raw| BoardColumn.new raw }
end

describe AgingWorkInProgressChart do
  let :chart do
    chart = AgingWorkInProgressChart.new
    chart.board_id = 1
    chart.all_boards = { 1 => load_complete_sample_board }
    chart.cycletime = defaultCycletimeConfig
    chart.issues = load_complete_sample_issues
    chart
  end

  context 'accumulated_status_ids_per_column' do
    it 'should accumulate properly' do
      chart.issues = load_complete_sample_issues.select { |issue| chart.cycletime.in_progress? issue }

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
      actual = chart.days_at_percentage_threshold_for_all_columns percentage: 100, issues: chart.issues
      expect(actual).to eq [0, 0, 0, 0]
    end

    it 'at 0%' do
      actual = chart.days_at_percentage_threshold_for_all_columns percentage: 0, issues: chart.issues
      expect(actual).to eq [1, 1, 81, 81]
    end
  end

  context 'column_for' do
    it 'should work' do
      actual = chart.column_for(issue: chart.issues[-1]).name
      expect(actual).to eq 'Review'
    end
  end

  it 'make _data_sets' do
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
end
