# frozen_string_literal: true

require './spec/spec_helper'

class MockAnonymizer < Anonymizer
  def random_phrase
    'random_phrase'
  end

  def random_name
    'random_name'
  end
end

describe Anonymizer do

  let(:anonymizer) do
    exporter = Exporter.new
    project_config = ProjectConfig.new(
      exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil
    )
    project_config.file_prefix 'sample'
    project_config.anonymize
    # project_config.run
    MockAnonymizer.new project_config: project_config, date_adjustment: -10
  end

  context 'anonymize_issue_keys_and_titles' do
    it 'should have renumbered all issue keys and changed summary' do
      issue = anonymizer.project_config.issues.first
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(issue.key).to eq 'ANON-1'
      expect(issue.summary).to eq 'random_phrase'
      expect(issue.assigned_to).to be_nil
    end

    it 'should have changed assigned_to if it was set' do
      issue = anonymizer.project_config.issues.first
      issue.raw['fields']['assignee'] = { 'displayName' => 'Fred' }
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(issue.assigned_to).to eq 'random_name'
    end

    it 'should have changed assigned_to if it was set' do
      issue = anonymizer.project_config.issues.first
      issue.raw['fields']['assignee'] = { 'displayName' => 'Fred' }
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(issue.assigned_to).to eq 'random_name'
    end

    it 'should have changed links' do
      issue = anonymizer.project_config.issues.first
      issue.raw['fields']['issuelinks'] = [
        {
          'inwardIssue' => {
            'key' => 'SP-15',
            'fields' => {
              'summary' => 'CLONE - Report of people checked in at an event'
            }
          }
        }
      ]

      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      links = issue.issue_links
      expect(links.size).to eq 1

      other_issue = links.first.other_issue
      expect(other_issue.key).to eq 'ANON-2'
      expect(other_issue.summary).to eq 'random_phrase'
    end
  end
end
