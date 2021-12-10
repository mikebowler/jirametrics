# frozen_string_literal: true

require './spec/spec_helper'

describe HtmlReportConfig do
  context 'date_that_percentage_of_issues_leave_statuses' do
    it '' do
      project_config = ProjectConfig.new exporter: nil, target_path: 'data/', jira_config: nil, block: nil
      project_config.file_prefix 'foo'
      file_config = FileConfig.new project_config: project_config, block: nil

      html_report_config = HtmlReportConfig.new file_config: file_config, block: nil
      issues = [load_issue('SP-1'), load_issue('SP-2'), load_issue('SP-10')]
      statuses = nil
      result = html_report_config.date_that_percentage_of_issues_leave_statuses(
        percentage: 85, issues: issues, statuses: statuses
      )
      expect(result).to eq 4
    end
  end
end
