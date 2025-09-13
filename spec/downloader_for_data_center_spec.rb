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
  let(:jira_gateway) { MockJiraGateway.new(file_system: file_system) }
  let(:downloader) do
    described_class.new(download_config: download_config, file_system: file_system, jira_gateway: jira_gateway)
      .tap do |d|
        d.init_gateway
      end
  end

  context 'download_issues' do
    it 'downloads issues' do
      url = '/rest/api/2/search?jql=filter%3D123&maxResults=100&startAt=0&expand=changelog&fields=*all'
      issue_json = { 'key' => 'ABC-123', 'fields' => {} }
      jira_gateway.when url: url, response: { 'issues' => [issue_json], 'total' => 1, 'maxResults' => 100 }
      board = sample_board
      board.raw['id'] = 2
      downloader.board_id_to_filter_id[2] = 123
      downloader.download_issues board: board

      expect(file_system.log_messages).to eq([
        'Downloading primary issues for board 2 from Jira DataCenter',
        'JQL: filter=123',
        'Downloaded 1-1 of 1 issues to spec/testdata/sample_issues/',
        'Downloading linked issues for board 2'
      ])
      expect(file_system.saved_json).to eq({
        'spec/testdata/sample_issues/ABC-123-2.json' =>
          '{"key":"ABC-123","fields":{},"exporter":{"in_initial_query":true}}'
      })
    end
  end

  context 'jira_search_by_jql' do
    it 'completes when no issues found' do
      url = '/rest/api/2/search?jql=project%3DABC&maxResults=100&startAt=0&expand=changelog&fields=*all'
      jira_gateway.when url: url, response: { 'issues' => [], 'total' => 0, 'maxResults' => 0 }

      board = sample_board
      board.raw['id'] = 2

      downloader.jira_search_by_jql jql: 'project=ABC', initial_query: true, board: board, path: '/abc'

      expect(file_system.log_messages).to eq(
        [
          'JQL: project=ABC',
          'Downloaded 1-0 of 0 issues to /abc'
        ]
      )
      expect(file_system.saved_json).to be_empty
    end

    it 'completes when one issue found' do
      url = '/rest/api/2/search?jql=project%3DABC&maxResults=100&startAt=0&expand=changelog&fields=*all'
      issue_json = {
        'key' => 'ABC-123',
        'fields' => {}
      }
      jira_gateway.when url: url, response: { 'issues' => [issue_json], 'total' => 1, 'maxResults' => 100 }

      board = sample_board
      board.raw['id'] = 2
      downloader.jira_search_by_jql jql: 'project=ABC', initial_query: true, board: board, path: '/abc'

      expect(file_system.log_messages).to eq(
        [
          'JQL: project=ABC',
          'Downloaded 1-1 of 1 issues to /abc'
        ]
      )
      expect(file_system.saved_json).to eq({
        '/abc/ABC-123-2.json' => '{"key":"ABC-123","fields":{},"exporter":{"in_initial_query":true}}'
      })
    end

    it 'follows pagination' do
      url = '/rest/api/2/search?jql=project%3DABC&maxResults=100&startAt=0&expand=changelog&fields=*all'
      issue_json = { 'key' => 'ABC-123', 'fields' => {} }
      jira_gateway.when url: url, response: { 'issues' => [issue_json], 'total' => 2, 'maxResults' => 1 }

      url = '/rest/api/2/search?jql=project%3DABC&maxResults=1&startAt=1&expand=changelog&fields=*all'
      issue_json = { 'key' => 'ABC-125', 'fields' => {} }
      jira_gateway.when url: url, response: { 'issues' => [issue_json], 'total' => 2, 'maxResults' => 1 }

      board = sample_board
      board.raw['id'] = 2

      downloader.jira_search_by_jql jql: 'project=ABC', initial_query: true, board: board, path: '/abc'

      expect(file_system.log_messages).to eq([
        'JQL: project=ABC',
        'Downloaded 1-1 of 2 issues to /abc',
        'Downloaded 2-2 of 2 issues to /abc'
      ])
      expect(file_system.saved_json).to eq({
        '/abc/ABC-123-2.json' => '{"key":"ABC-123","fields":{},"exporter":{"in_initial_query":true}}',
        '/abc/ABC-125-2.json' => '{"key":"ABC-125","fields":{},"exporter":{"in_initial_query":true}}'
      })
    end
  end
end