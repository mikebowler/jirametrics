# frozen_string_literal: true

require './spec/spec_helper'

describe AggregateConfig do
  context 'date_range_to_time_range' do
    it '' do
      date_range = Date.parse('2022-01-01')..Date.parse('2022-01-02')
      expected = Time.parse('2022-01-01T00:00:00Z')..Time.parse('2022-01-02T23:59:59Z')
      offset = 'Z'
      subject = AggregateConfig.new project_config: nil, block: nil

      expect(subject.date_range_to_time_range(date_range: date_range, timezone_offset: offset)).to eq expected
    end
  end

  context 'include_issues_from' do
    it 'should not allow aggregating projects from different jira instances' do
      exporter = Exporter.new
      target_path = 'spec/testdata/'

      project1 = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'foo'
      )
      project1.file_prefix 'sample'
      project1.run
      project1.jira_url = 'http://foo.com'
      exporter.project_configs << project1

      project2 = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'bar'
      )
      project2.file_prefix 'sample'
      project2.run
      project2.jira_url = 'http://bar.com'
      exporter.project_configs << project2

      project3 = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'aggregate'
      )
      subject = AggregateConfig.new project_config: project3, block: nil
      subject.include_issues_from 'foo'
      expect { subject.include_issues_from 'bar' }.to raise_error(
        'Not allowed to aggregate projects from different Jira instances: "http://foo.com" and "http://bar.com"'
      )
    end
  end
end
