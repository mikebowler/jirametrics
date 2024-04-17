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
    project_config.load_status_category_mappings
    project_config.load_all_boards

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
      issue1 = load_issue('SP-1')
      anonymizer.project_config.issues << issue1
      issue1.raw['fields']['issuelinks'] = [
        {
          'inwardIssue' => {
            'key' => 'SP-15',
            'fields' => {
              'summary' => 'CLONE - Report of people checked in at an event'
            }
          }
        }
      ]

      anonymizer.anonymize_issue_keys_and_titles(issues: [issue1])
      links = issue1.issue_links
      expect(links.size).to eq 1

      other_issue = links.first.other_issue
      expect(other_issue.key).to eq 'ANON-2'
      expect(other_issue.summary).to eq 'random_phrase'
    end
  end

  context 'Board.status_ids_in_or_right_of_column' do
    let(:board) { anonymizer.project_config.all_boards[1] }

    it 'should work when not anonymized' do
      expect(board.visible_columns.collect(&:name)).to eq ['Ready', 'In Progress', 'Review', 'Done']
      expect(board.status_ids_in_or_right_of_column('Review')).to eq [10_011, 10_002]
    end

    it 'should still work after anonymization' do
      anonymizer.anonymize_column_names
      expect(board.visible_columns.collect(&:name)).to eq %w[Column-A Column-B Column-C Column-D]
      expect(board.status_ids_in_or_right_of_column('Review')).to eq [10_011, 10_002]
    end
  end
end
