# frozen_string_literal: true

require './spec/spec_helper'

describe AggregateConfig do
  let(:exporter) do
    Exporter.new(file_system: MockFileSystem.new).tap do |exporter|
      exporter.file_system.when_loading file: 'spec/testdata/sample_board_1_configuration.json', json: :not_mocked
      exporter.file_system.when_loading file: 'spec/testdata//sample_statuses.json', json: :not_mocked
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: :not_mocked
    end
  end
  let(:target_path) { 'spec/testdata/' }
  let(:aggregated_project) do

    ProjectConfig.new(
      exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'aggregate'
    )
  end

  context 'include_issues_from' do
    it 'raises error if project not found' do
      project = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'aggregate'
      )
      subject = described_class.new project_config: project, block: nil

      subject.include_issues_from 'foobar'
      expect(exporter.file_system.log_messages).to eq [
        'Warning: Aggregated project "aggregate" is attempting to load project "foobar" but it ' \
          'can\'t be found. Is it disabled?'
      ]
    end

    it 'does not allow aggregating projects from different jira instances' do
      project1 = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'foo'
      )
      exporter.file_system.when_foreach root: 'spec/testdata/', result: []
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
      subject = described_class.new project_config: project3, block: nil
      subject.include_issues_from 'foo'
      expect { subject.include_issues_from 'bar' }.to raise_error(
        'Not allowed to aggregate projects from different Jira instances: "http://foo.com" and ' \
          '"http://bar.com". For project bar'
      )
    end

    it 'pulls issues from project when no file sections' do
      solo_project = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'solo'
      )
      exporter.file_system.when_foreach root: 'spec/testdata/', result: []
      solo_project.file_prefix 'sample'
      solo_project.run
      solo_project.issues << empty_issue(key: 'SP-1', created: '2023-01-01')
      exporter.project_configs << solo_project

      subject = described_class.new project_config: aggregated_project, block: nil
      subject.include_issues_from 'solo'
      expect(aggregated_project.issues.collect(&:key)).to eq %w[SP-1]
    end
  end

  context 'find_time_range' do
    it 'raises error if no projects found' do
      subject = described_class.new project_config: aggregated_project, block: nil
      expect { subject.find_time_range projects: [] }.to raise_error(
        "Can't calculate aggregated range as no projects were included."
      )
    end

    it 'takes the range from a single project' do
      project1 = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'foo'
      )
      project1.time_range = to_time('2024-01-01')..to_time('2024-01-02')

      subject = described_class.new project_config: aggregated_project, block: nil
      expect(subject.find_time_range projects: [project1]).to eq to_time('2024-01-01')..to_time('2024-01-02')
    end

    it 'takes the full range across multiple projects' do
      project1 = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'foo'
      )
      project1.time_range = to_time('2024-01-01')..to_time('2024-01-02')

      project2 = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'foo'
      )
      project2.time_range = to_time('2024-01-03')..to_time('2024-01-04')

      project3 = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'foo'
      )
      project3.time_range = to_time('2024-01-02')..to_time('2024-01-03')

      subject = described_class.new project_config: aggregated_project, block: nil
      expect(subject.find_time_range projects: [project1, project2, project3]).to eq(
        to_time('2024-01-01')..to_time('2024-01-04')
      )
    end
  end

  context 'adjust_issue_links' do
    it 'adjusts link' do
      issue1 = load_issue('SP-1')
      issue2 = load_issue('SP-2')
      issue1.issue_links << IssueLink.new(origin: issue1, raw: {
        'type' => { 'inward' => 'Clones' },
        'inwardIssue' => { 'key' => 'SP-2' }
      })
      issue1.issue_links << IssueLink.new(origin: issue1, raw: {
        'type' => { 'inward' => 'Clones' },
        'inwardIssue' => { 'key' => 'NOTFOUND-4' } # So we pass through all logic
      })
      issues = [issue1, issue2]
      subject = described_class.new project_config: aggregated_project, block: nil
      subject.adjust_issue_links issues: issues
      expect(issue1.issue_links.first.other_issue).to be issue2
    end
  end

  context 'evaluate_next_level' do
    it 'raises error if no projects set' do
      subject = described_class.new project_config: aggregated_project, block: empty_config_block
      expect { subject.evaluate_next_level }.to raise_error(
        'aggregate: When aggregating, you must include at least one other project'
      )
    end
  end
end
