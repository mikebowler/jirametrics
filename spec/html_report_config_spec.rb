# frozen_string_literal: true

require './spec/spec_helper'

class MockIssue
  attr_reader :created, :first_status_change_after_created, :type, :summary

  def initialize key:, start:, stop:, type:
    @key = key
    @created = start
    @first_status_change_after_created = stop
    @type = type
    @summary = "#{@key} summary"
  end

  def datetime string
    return nil if string.nil?

    DateTime.parse string
  end
end

describe HtmlReportConfig do
  context 'dataset_by_age chart_data:, age_range:, date_range:, label:' do
    it '' do
      project_config = ProjectConfig.new exporter: nil, target_path: 'data/', jira_config: nil, block: nil
      project_config.file_prefix 'foo'
      file_config = FileConfig.new project_config: project_config, block: nil

      html_report_config = HtmlReportConfig.new file_config: file_config, block: nil
      html_report_config.cycletime do
        start_at created
        stop_at first_status_change_after_created
      end
      issues = [
        MockIssue.new(key: 'M-1', start: '2021-01-01T12:00:00 00:00', stop: '2021-01-03T12:00:00 00:00', type: 'Story')
      ]
      statuses = nil
      result = html_report_config.dataset_by_age chart_data: [], age_range: 2..5, date_range:, label:(
        percentage: 85, issues: issues, status_ids: statuses
      )
      expect(result).to eq 3
    end
  end
end
