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
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:project_config) do
    ProjectConfig.new(
      exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil
    ).tap do |p|
      p.file_prefix 'sample'
      p.load_status_category_mappings
      p.load_all_boards
      p.board id: 1 do
        cycletime do
          start_at first_time_in_status_category(:indeterminate)
          stop_at first_time_in_status_category(:done)
        end
      end
      p.time_range = to_time('2021-06-01')..to_time('2021-09-01')
    end
  end
  let(:anonymizer) do
    exporter.file_system.when_loading file: 'spec/complete_sample/sample_board_1_configuration.json', json: :not_mocked
    exporter.file_system.when_loading file: 'spec/complete_sample/sample_statuses.json', json: :not_mocked
    exporter.file_system.when_loading file: 'spec/complete_sample/sample_meta.json', json: :not_mocked
    exporter.file_system.when_foreach root: 'spec/complete_sample/sample_issues', result: :not_mocked
    [1, 2, 5, 7, 8, 11].each do |issue_num|
      exporter.file_system.when_loading(
        file: "spec/complete_sample/sample_issues/SP-#{issue_num}.json",
        json: :not_mocked
      )
    end

    MockAnonymizer.new project_config: project_config, date_adjustment: -10
  end

  context 'anonymize_issue_keys_and_titles' do
    it 'has renumbered all issue keys and changed summary' do
      issue = anonymizer.project_config.issues.first
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(issue.key).to eq 'ANON-1'
      expect(issue.summary).to eq 'random_phrase'
      expect(issue.assigned_to).to be_nil
    end

    it 'has changed assigned_to if it was set' do
      issue = anonymizer.project_config.issues.first
      issue.raw['fields']['assignee'] = { 'displayName' => 'Fred' }
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(issue.assigned_to).to eq 'random_name'
    end

    it 'has changed links' do
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

    it 'works when not anonymized' do
      expect(board.visible_columns.collect(&:name)).to eq ['Ready', 'In Progress', 'Review', 'Done']
      expect(board.status_ids_in_or_right_of_column('Review')).to eq [10_011, 10_002]
    end

    it 'still works after anonymization' do
      anonymizer.anonymize_column_names
      expect(board.visible_columns.collect(&:name)).to eq %w[Column-A Column-B Column-C Column-D]
      expect(board.status_ids_in_or_right_of_column('Review')).to eq [10_011, 10_002]
    end
  end

  context 'shift_all_dates' do
    it 'changes nothing when shift is zero' do
      issue1 = anonymizer.project_config.issues.find { |i| i.key == 'SP-1' }
      changes = issue1.changes.collect { |c| "#{c.field}  #{c.time}" }

      anonymizer.shift_all_dates date_adjustment: 0
      expect(changes).to eq [
        'status  2021-06-18 18:41:29 +0000',
        'priority  2021-06-18 18:41:29 +0000',
        'status  2021-06-18 18:43:34 +0000',
        'status  2021-06-18 18:44:21 +0000',
        'Flagged  2021-08-29 18:04:39 +0000',
        'status  2021-12-14 00:30:15 +0000'
      ]
      expect(issue1.updated.to_s).to eql '2021-12-14 00:30:15 +0000'
      expect(exporter.file_system.log_messages).to eq [
        'Shifting all dates by 0 days'
      ]
    end

    it 'shifts everything by one day' do
      issue1 = anonymizer.project_config.issues.find { |i| i.key == 'SP-1' }
      changes = issue1.changes.collect { |c| "#{c.field}  #{c.time}" }

      anonymizer.shift_all_dates date_adjustment: 1
      expect(changes).to eq [
        'status  2021-06-18 18:41:29 +0000',
        'priority  2021-06-18 18:41:29 +0000',
        'status  2021-06-18 18:43:34 +0000',
        'status  2021-06-18 18:44:21 +0000',
        'Flagged  2021-08-29 18:04:39 +0000',
        'status  2021-12-14 00:30:15 +0000'
      ]
      expect(issue1.updated.to_s).to eql '2021-12-15 00:30:15 +0000'
      expect(exporter.file_system.log_messages).to eq [
        'Shifting all dates by 1 day'
      ]
    end
  end
end
