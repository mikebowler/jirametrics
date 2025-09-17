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

  context 'create' do
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
      expect(instance).to be_instance_of DownloaderForDataCenter
    end
  end

  context 'search_for_issues' do
    it 'completes when no issues found' do
      url = '/rest/api/2/search?jql=project%3DABC&maxResults=100&startAt=0&fields=updated'
      jira_gateway.when url: url, response: { 'issues' => [], 'total' => 0, 'maxResults' => 0 }

      board = sample_board
      board.raw['id'] = 2

      downloader.search_for_issues jql: 'project=ABC', board_id: board.id, path: '/abc'

      expect(file_system.log_messages).to eq(
        [
          'JQL: project=ABC',
          'Found 0 issues'
        ]
      )
      expect(file_system.saved_json).to be_empty
    end

    it 'follows pagination' do
      url = '/rest/api/2/search?jql=project%3DABC&maxResults=100&startAt=0&fields=updated'
      issue_json = {
        'key' => 'ABC-123',
        'fields' => { 'updated' => '2025-01-01T00:00:00:00 +0000'
        }
      }
      jira_gateway.when url: url, response: { 'issues' => [issue_json], 'total' => 2, 'maxResults' => 1 }

      url = '/rest/api/2/search?jql=project%3DABC&maxResults=1&startAt=1&fields=updated'
      issue_json = {
        'key' => 'ABC-125',
        'fields' => { 'updated' => '2025-01-01T00:00:00:00 +0000'
        }
      }
      jira_gateway.when url: url, response: { 'issues' => [issue_json], 'total' => 2, 'maxResults' => 1 }

      board = sample_board
      board.raw['id'] = 2

      downloader.search_for_issues jql: 'project=ABC', board_id: board.id, path: '/abc'

      expect(file_system.log_messages).to eq([
        'JQL: project=ABC', 'Found 1 issues', 'Found 1 issues'
      ])
    end
  end
end