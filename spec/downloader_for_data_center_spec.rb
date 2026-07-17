# frozen_string_literal: true

require './spec/spec_helper'
require './spec/mock_file_system'
require './spec/mock_jira_gateway'

def mock_download_config
  exporter = Exporter.new
  jira_config = {
    'url' => 'https://example.com',
    'email' => 'bugs_bunny@example.com',
    'api_token' => 'carrots'
  }
  project = ProjectConfig.new(
    exporter: exporter, target_path: 'spec/testdata/', jira_config: jira_config, block: nil
  )
  project.file_prefix 'sample'

  DownloadConfig.new project_config: project, block: nil
end

describe DownloaderForDataCenter do
  let(:download_config) { mock_download_config }
  let(:file_system) { MockFileSystem.new }
  let(:jira_gateway) do
    MockJiraGateway.new(
      file_system: file_system,
      jira_config: { 'url' => 'https://example.com' },
      settings: { 'ignore_ssl_errors' => false }
    )
  end
  let(:downloader) do
    described_class.new(
      download_config: download_config,
      file_system: file_system,
      jira_gateway: jira_gateway
    )
  end

  describe '.create' do
    it 'defaults to data centre for non atlassian domains' do
      jira_gateway = MockJiraGateway.new(
        file_system: file_system,
        jira_config: { 'url' => 'https://example.com' },
        settings: { 'ignore_ssl_errors' => false }
      )
      instance = Downloader.create(
        download_config: download_config,
        file_system: file_system,
        jira_gateway: jira_gateway
      )
      expect(instance).to be_instance_of DownloaderForDataCenter # rubocop:disable RSpec/DescribedClass
    end
  end

  describe '#download_issues' do
    let(:raw_issue) do
      raw_issue = empty_issue(created: '2025-01-01').raw
      raw_issue['changelog'] = nil
      raw_issue['id'] = '123'
      raw_issue
    end

    it 'downloads' do
      jira_gateway.when(
        url: '/rest/api/2/search?jql=filter%3D3&maxResults=100&startAt=0&expand=changelog&fields=*all',
        response: {
          'maxResults' => 100,
          'total' => 1,
          'issues' => [raw_issue]
        }
      )
      jira_gateway.when(
        url: "/rest/api/2/issue/#{raw_issue['key']}/worklog?startAt=0&maxResults=100",
        response: { 'total' => 0, 'worklogs' => [] }
      )
      file_system.when_loading(file: "spec/testdata/sample_issues/#{raw_issue['key']}-1.json", json: raw_issue)
      board = sample_board
      downloader.board_id_to_filter_id[board.id] = 3
      downloader.download_issues board: board
      expect(file_system.log_messages).to eq([
        'Downloading primary issues for board 1',
        'JQL: filter=3',
        'Downloaded 1-1 of 1 issues to spec/testdata/sample_issues/',
        'Downloading linked issues for board 1'
      ])
    end
  end

  describe '#enhance_issue_with_worklogs' do
    it 'fetches all worklogs for a single issue with pagination' do
      issue_path = 'spec/testdata/TEST-1-1.json'
      original_issue = {
        'key' => 'TEST-1',
        'id' => '123',
        'fields' => { 'summary' => 'Test' },
        'worklog' => { 'total' => 0, 'worklogs' => [] }
      }

      file_system.when_loading(file: issue_path, json: original_issue)

      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-1/worklog?startAt=0&maxResults=100',
        response: {
          'total' => 150,
          'startAt' => 0,
          'maxResults' => 100,
          'worklogs' => (1..100).map { |i| { 'id' => i.to_s, 'timeSpentSeconds' => 3600 * i } }
        }
      )

      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-1/worklog?startAt=100&maxResults=100',
        response: {
          'total' => 150,
          'startAt' => 100,
          'maxResults' => 100,
          'worklogs' => (101..150).map { |i| { 'id' => i.to_s, 'timeSpentSeconds' => 3600 * i } }
        }
      )

      downloader.enhance_issue_with_worklogs(issue_key: 'TEST-1', issue_path: issue_path)

      saved_issue = file_system.saved_json_expanded[issue_path]
      aggregate_failures do
        expect(saved_issue['fields']['worklog']['total']).to eq(150)
        expect(saved_issue['fields']['worklog']['worklogs'].size).to eq(150)
      end
    end

    it 'advances startAt by actual items received, not max_results' do
      issue_path = 'spec/testdata/TEST-3-1.json'
      original_issue = { 'key' => 'TEST-3', 'id' => '125', 'fields' => { 'summary' => 'Test' } }
      file_system.when_loading(file: issue_path, json: original_issue)

      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-3/worklog?startAt=0&maxResults=100',
        response: {
          'total' => 150,
          'worklogs' => (1..80).map { |i| { 'id' => i.to_s } }
        }
      )
      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-3/worklog?startAt=80&maxResults=100',
        response: {
          'total' => 150,
          'worklogs' => (81..150).map { |i| { 'id' => i.to_s } }
        }
      )

      downloader.enhance_issue_with_worklogs(issue_key: 'TEST-3', issue_path: issue_path)

      saved_issue = file_system.saved_json_expanded[issue_path]
      expect(saved_issue['fields']['worklog']['worklogs'].size).to eq(150)
    end

    it 'paginates correctly when server caps page size below requested max' do
      issue_path = 'spec/testdata/TEST-4-1.json'
      original_issue = { 'key' => 'TEST-4', 'id' => '126', 'fields' => { 'summary' => 'Test' } }
      file_system.when_loading(file: issue_path, json: original_issue)

      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-4/worklog?startAt=0&maxResults=1',
        response: { 'total' => 3, 'worklogs' => [{ 'id' => '1' }] }
      )
      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-4/worklog?startAt=1&maxResults=1',
        response: { 'total' => 3, 'worklogs' => [{ 'id' => '2' }] }
      )
      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-4/worklog?startAt=2&maxResults=1',
        response: { 'total' => 3, 'worklogs' => [{ 'id' => '3' }] }
      )

      downloader.enhance_issue_with_worklogs(issue_key: 'TEST-4', issue_path: issue_path, max_results: 1)

      saved_issue = file_system.saved_json_expanded[issue_path]
      aggregate_failures do
        expect(saved_issue['fields']['worklog']['total']).to eq(3)
        expect(saved_issue['fields']['worklog']['worklogs'].size).to eq(3)
      end
    end

    it 'handles issues with no worklogs' do
      issue_path = 'spec/testdata/TEST-2-1.json'
      original_issue = {
        'key' => 'TEST-2',
        'id' => '124',
        'fields' => { 'summary' => 'Test' }
      }

      file_system.when_loading(file: issue_path, json: original_issue)

      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-2/worklog?startAt=0&maxResults=100',
        response: {
          'total' => 0,
          'startAt' => 0,
          'maxResults' => 100,
          'worklogs' => []
        }
      )

      downloader.enhance_issue_with_worklogs(issue_key: 'TEST-2', issue_path: issue_path)

      saved_issue = file_system.saved_json_expanded[issue_path]
      aggregate_failures do
        expect(saved_issue['fields']['worklog']['total']).to eq(0)
        expect(saved_issue['fields']['worklog']['worklogs']).to be_empty
      end
    end
  end
end
