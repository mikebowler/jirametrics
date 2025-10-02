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
      expect(instance).to be_instance_of DownloaderForDataCenter # rubocop:disable RSpec/DescribedClass
    end
  end

  context 'download_issues' do
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
end