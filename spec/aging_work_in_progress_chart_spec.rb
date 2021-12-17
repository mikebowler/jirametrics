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
end
