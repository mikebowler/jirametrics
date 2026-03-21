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

    it 'clears the description' do
      issue = anonymizer.project_config.issues.first
      issue.raw['fields']['description'] = 'Secret description'
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(issue.raw['fields']['description']).to be_nil
    end

    it 'anonymizes the creator' do
      issue = anonymizer.project_config.issues.first
      issue.raw['fields']['creator'] = {
        'displayName' => 'Real Person',
        'name' => 'rperson',
        'emailAddress' => 'real@example.com',
        'avatarUrls' => { '16x16' => 'https://example.com/avatar.png' }
      }
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      creator = issue.raw['fields']['creator']
      expect(creator['displayName']).to eq 'random_name'
      expect(creator['name']).to eq 'random_name'
      expect(creator['emailAddress']).to be_nil
      expect(creator['avatarUrls']).to be_nil
    end

    it 'anonymizes change history authors' do
      issue = anonymizer.project_config.issues.first
      author = {
        'displayName' => 'Real Person',
        'name' => 'rperson',
        'emailAddress' => 'real@example.com',
        'avatarUrls' => { '16x16' => 'https://example.com/avatar.png' }
      }
      issue.changes << ChangeItem.new(
        raw: { 'field' => 'priority', 'to' => '3', 'toString' => 'Medium', 'from' => nil, 'fromString' => nil },
        time: to_time('2021-07-01'), author_raw: author
      )
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(author['displayName']).to eq 'random_name'
      expect(author['name']).to eq 'random_name'
      expect(author['emailAddress']).to be_nil
      expect(author['avatarUrls']).to be_nil
    end

    it 'only anonymizes the same author_raw hash once even when shared across changes' do
      issue = anonymizer.project_config.issues.first
      issue.raw['fields']['creator'] = nil
      issue.changes.clear
      author = { 'displayName' => 'Real Person', 'name' => 'rperson' }
      issue.changes << ChangeItem.new(
        raw: { 'field' => 'priority', 'to' => '3', 'toString' => 'Medium', 'from' => nil, 'fromString' => nil },
        time: to_time('2021-07-01'), author_raw: author
      )
      issue.changes << ChangeItem.new(
        raw: { 'field' => 'priority', 'to' => '2', 'toString' => 'High', 'from' => '3', 'fromString' => 'Medium' },
        time: to_time('2021-07-02'), author_raw: author
      )
      expect(anonymizer).to receive(:random_name).once.and_return('random_name')
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
    end

    it 'clears comment text in change history' do
      issue = anonymizer.project_config.issues.first
      change = ChangeItem.new(
        raw: { 'field' => 'comment', 'to' => '1', 'toString' => 'Secret comment', 'from' => nil, 'fromString' => nil },
        time: to_time('2021-07-01'), author_raw: nil, artificial: true
      )
      issue.changes << change
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(change.value).to be_nil
    end

    it 'clears description change text in change history' do
      issue = anonymizer.project_config.issues.first
      change = ChangeItem.new(
        raw: { 'field' => 'description', 'to' => nil, 'toString' => 'New secret text',
               'from' => nil, 'fromString' => 'Old secret text' },
        time: to_time('2021-07-01'), author_raw: nil, artificial: true
      )
      issue.changes << change
      anonymizer.anonymize_issue_keys_and_titles(issues: [issue])
      expect(change.value).to be_nil
      expect(change.old_value).to be_nil
    end
  end

  context 'anonymize_labels_and_components' do
    it 'clears labels and component names' do
      issue = anonymizer.project_config.issues.first
      issue.raw['fields']['labels'] = ['Customer-XYZ', 'Priority-1']
      issue.raw['fields']['components'] = [{ 'name' => 'Backend' }, { 'name' => 'API' }]
      anonymizer.anonymize_labels_and_components
      expect(issue.labels).to be_empty
      expect(issue.component_names).to be_empty
    end
  end

  context 'anonymize_sprints' do
    let(:board) { anonymizer.project_config.all_boards[1] }

    it 'anonymizes sprint names' do
      board.sprints << Sprint.new(
raw: { 'id' => 1, 'state' => 'closed', 'name' => 'Sprint Alpha', 'activatedDate' => '2021-06-01T00:00:00.000Z', 
'endDate' => '2021-06-15T00:00:00.000Z', 'completeDate' => '2021-06-15T00:00:00.000Z' }, timezone_offset: '+00:00')
      board.sprints << Sprint.new(
raw: { 'id' => 2, 'state' => 'active', 'name' => 'Sprint Beta', 'activatedDate' => '2021-06-16T00:00:00.000Z', 
'endDate' => '2021-06-30T00:00:00.000Z' }, timezone_offset: '+00:00')
      anonymizer.anonymize_sprints
      expect(board.sprints.collect(&:name)).to eq ['Sprint-1', 'Sprint-2']
    end

    it 'assigns the same anonymized name to sprints with the same original name' do
      board.sprints << Sprint.new(
raw: { 'id' => 1, 'state' => 'active', 'name' => 'Sprint Alpha', 'activatedDate' => '2021-06-01T00:00:00.000Z', 
'endDate' => '2021-06-15T00:00:00.000Z' }, timezone_offset: '+00:00')
      board.sprints << Sprint.new(
raw: { 'id' => 2, 'state' => 'active', 'name' => 'Sprint Alpha', 'activatedDate' => '2021-06-01T00:00:00.000Z', 
'endDate' => '2021-06-15T00:00:00.000Z' }, timezone_offset: '+00:00')
      anonymizer.anonymize_sprints
      expect(board.sprints.collect(&:name)).to eq ['Sprint-1', 'Sprint-1']
    end
  end

  context 'anonymize_fix_versions' do
    it 'anonymizes fix version names consistently across issues' do
      issue1 = anonymizer.project_config.issues.first
      issue2 = anonymizer.project_config.issues[1]
      issue1.raw['fields']['fixVersions'] = [{ 'id' => '10', 'name' => 'v1.0', 'released' => false }]
      issue2.raw['fields']['fixVersions'] = 
[{ 'id' => '10', 'name' => 'v1.0', 'released' => false }, { 'id' => '20', 'name' => 'v2.0', 'released' => false }]
      anonymizer.anonymize_fix_versions
      expect(issue1.raw['fields']['fixVersions'].collect { |fv| fv['name'] }).to eq ['Version-1']
      expect(issue2.raw['fields']['fixVersions'].collect { |fv| fv['name'] }).to eq ['Version-1', 'Version-2']
    end
  end

  context 'anonymize_server_url' do
    let(:board) { anonymizer.project_config.all_boards[1] }

    it 'replaces the real Jira domain in board.raw[self]' do
      anonymizer.anonymize_server_url
      expect(board.raw['self']).to start_with('https://anon.example.com/')
      expect(board.raw['self']).not_to include('improvingflow')
    end

    it 'still allows server_url_prefix to work after anonymization' do
      anonymizer.anonymize_server_url
      expect(board.server_url_prefix).to eq 'https://anon.example.com'
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

    it 'shifts time_range by the same number of days as the changes' do
      anonymizer.shift_all_dates date_adjustment: 5
      expect(anonymizer.project_config.time_range.begin.to_date.to_s).to eq '2021-06-06'
      expect(anonymizer.project_config.time_range.end.to_date.to_s).to eq '2021-09-06'
    end
  end
end
