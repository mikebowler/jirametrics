# frozen_string_literal: true

require './spec/spec_helper'

def complete_sample_issues
  json = JSON.parse(File.read('./spec/complete_sample/sample_0.json'))
  json['issues'].collect { |raw| Issue.new raw: raw }
end

def complete_sample_board_metadata
  json = JSON.parse(File.read('./spec/complete_sample/sample_board_1_configuration.json'))
  json['columnConfig']['columns'].collect { |raw| BoardColumn.new raw }
end

describe AgingWorkInProgressChart do
  context 'accumulated_status_ids_per_column' do
    it 'should accumulate properly' do
      chart = AgingWorkInProgressChart.new
      chart.board_metadata = complete_sample_board_metadata
      chart.cycletime = defaultCycletimeConfig
      chart.issues = complete_sample_issues.select { |issue| chart.cycletime.in_progress? issue }

      actual = chart.accumulated_status_ids_per_column
      expect(actual).to eq [
        ['Backlog',     [10_002, 10_011, 3, 10_001, 10_000]],
        ['Ready',       [10_002, 10_011, 3, 10_001]],
        ['In Progress', [10_002, 10_011, 3]],
        ['Review',      [10_002, 10_011]],
        ['Done',        [10_002]]
      ]
    end
  end

  context 'ages_of_issues_that_crossed_column_boundary' do
    it 'should handle no issues' do
      chart = AgingWorkInProgressChart.new
      chart.board_metadata = complete_sample_board_metadata
      chart.cycletime = defaultCycletimeConfig
      issues = []

      actual = chart.ages_of_issues_that_crossed_column_boundary issues: issues, status_ids: [10_002, 10_011]
      expect(actual).to eq []
    end

    it 'should handle no status ids' do
      chart = AgingWorkInProgressChart.new
      chart.board_metadata = complete_sample_board_metadata
      chart.cycletime = defaultCycletimeConfig
      issues = complete_sample_issues

      actual = chart.ages_of_issues_that_crossed_column_boundary issues: issues, status_ids: []
      expect(actual).to eq []
    end

    it 'should handle happy path' do
      chart = AgingWorkInProgressChart.new
      chart.board_metadata = complete_sample_board_metadata
      chart.cycletime = defaultCycletimeConfig
      issues = complete_sample_issues

      actual = chart.ages_of_issues_that_crossed_column_boundary issues: issues, status_ids: [10_002, 10_011, 3]
      expect(actual).to eq [179, 72, 1]
    end
  end

  context 'days_at_percentage_threshold_for_all_columns' do
    it 'at 100%' do
      chart = AgingWorkInProgressChart.new
      chart.board_metadata = complete_sample_board_metadata
      chart.cycletime = defaultCycletimeConfig
      issues = complete_sample_issues

      actual = chart.days_at_percentage_threshold_for_all_columns percentage: 100, issues: issues
      expect(actual).to eq [0, 0, 0, 0, 0]
    end

    it 'at 0%' do
      chart = AgingWorkInProgressChart.new
      chart.board_metadata = complete_sample_board_metadata
      chart.cycletime = defaultCycletimeConfig
      issues = complete_sample_issues

      actual = chart.days_at_percentage_threshold_for_all_columns percentage: 0, issues: issues
      expect(actual).to eq [1, 1, 1, 80, 80]
    end
  end

  context 'column_for' do
    it 'should work' do
      chart = AgingWorkInProgressChart.new
      chart.board_metadata = complete_sample_board_metadata
      chart.cycletime = defaultCycletimeConfig
      issues = complete_sample_issues

      actual = chart.column_for(issue: issues[-1]).name
      expect(actual).to eq 'Review'
    end
  end

  it 'make_data_sets' do
    chart = AgingWorkInProgressChart.new
    chart.board_metadata = complete_sample_board_metadata
    chart.cycletime = defaultCycletimeConfig
    chart.issues = complete_sample_issues

    expect(chart.make_data_sets).to eq([
      {
        'backgroundColor' => 'green',
        'data' => [
          {
            'title' => ['SP-11 : Report of all orders for an event (182 days)'],
            'x' => 'Ready',
            'y' => 182
          },
          {
            'title' => ['SP-8 : Refund ticket for individual order (182 days)'],
             'x' => 'In Progress',
             'y' => 182
          },
          {
            'title' => ['SP-7 : Purchase ticket with Apple Pay (182 days)'],
             'x' => 'Ready',
             'y' => 182
          },
          {
            'title' => ['SP-2 : Update existing event (182 days)'],
             'x' => 'Ready',
             'y' => 182
          },
          {
            'title' => ['SP-1 : Create new draft event (182 days)'],
            'x' => 'Review',
            'y' => 182
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
       'data' => [179, 179, 179, 80],
       'label' => '85%',
       'type' => 'bar'
     }
    ])
  end
end
