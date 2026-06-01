# frozen_string_literal: true

require './spec/spec_helper'
require './spec/mock_file_system'
require './spec/mock_jira_gateway'

describe 'WorklogHelper' do
  let(:file_system) { MockFileSystem.new }
  let(:exporter) { Exporter.new }
  let(:jira_config) { { 'url' => 'https://example.atlassian.com', 'email' => 'test@example.com', 'api_token' => 'token' } }
  let(:project_config) do
    ProjectConfig.new(exporter: exporter, target_path: 'spec/testdata/', jira_config: jira_config, block: nil)
  end
  let(:download_config) { DownloadConfig.new(project_config: project_config, block: nil) }

  let(:jira_gateway) do
    MockJiraGateway.new(
      file_system: file_system,
      jira_config: jira_config,
      settings: { 'ignore_ssl_errors' => false }
    )
  end

  context 'DownloaderForCloud#attach_worklogs_to_issues' do
    let(:downloader) do
      DownloaderForCloud.new(
        download_config: download_config,
        file_system: file_system,
        jira_gateway: jira_gateway
      )
    end

    it 'fetches all worklogs with pagination' do
      issue_datas = [
        DownloadIssueData.new(key: 'TEST-1'),
        DownloadIssueData.new(key: 'TEST-2')
      ]

      issue_jsons = [
        { 'id' => '1', 'key' => 'TEST-1' },
        { 'id' => '2', 'key' => 'TEST-2' }
      ]

      # First page response with more data
      jira_gateway.when(
        url: '/rest/api/3/issue/worklog/bulkfetch',
        response: {
          'issues' => [
            {
              'issueId' => '1',
              'worklogs' => [
                { 'id' => '100', 'timeSpentSeconds' => 3600 },
                { 'id' => '101', 'timeSpentSeconds' => 1800 }
              ]
            },
            {
              'issueId' => '2',
              'worklogs' => [
                { 'id' => '102', 'timeSpentSeconds' => 7200 }
              ]
            }
          ],
          'nextPageToken' => 'token123'
        }
      )

      # Second page response with no more pages
      jira_gateway.when(
        url: '/rest/api/3/issue/worklog/bulkfetch',
        response: {
          'issues' => [
            {
              'issueId' => '1',
              'worklogs' => [
                { 'id' => '103', 'timeSpentSeconds' => 900 }
              ]
            },
            {
              'issueId' => '2',
              'worklogs' => []
            }
          ],
          'nextPageToken' => nil
        }
      )

      downloader.attach_worklogs_to_issues(issue_datas: issue_datas, issue_jsons: issue_jsons)

      # Verify TEST-1 has all 3 worklogs
      expect(issue_jsons[0]['worklog']['total']).to eq(3)
      expect(issue_jsons[0]['worklog']['worklogs'].size).to eq(3)

      # Verify TEST-2 has 1 worklog
      expect(issue_jsons[1]['worklog']['total']).to eq(1)
      expect(issue_jsons[1]['worklog']['worklogs'].size).to eq(1)
    end

    it 'handles issues with no worklogs' do
      issue_datas = [DownloadIssueData.new(key: 'TEST-1')]
      issue_jsons = [{ 'id' => '1', 'key' => 'TEST-1' }]

      jira_gateway.when(
        url: '/rest/api/3/issue/worklog/bulkfetch',
        response: {
          'issues' => [
            {
              'issueId' => '1',
              'worklogs' => []
            }
          ],
          'nextPageToken' => nil
        }
      )

      downloader.attach_worklogs_to_issues(issue_datas: issue_datas, issue_jsons: issue_jsons)

      expect(issue_jsons[0]['worklog']['total']).to eq(0)
      expect(issue_jsons[0]['worklog']['worklogs']).to be_empty
    end
  end

  context 'DownloaderForDataCenter#enhance_issue_with_worklogs' do
    let(:downloader) do
      DownloaderForDataCenter.new(
        download_config: download_config,
        file_system: file_system,
        jira_gateway: jira_gateway
      )
    end

    it 'fetches all worklogs for a single issue with pagination' do
      issue_path = 'spec/testdata/TEST-1-1.json'
      original_issue = {
        'key' => 'TEST-1',
        'id' => '123',
        'fields' => { 'summary' => 'Test' },
        'worklog' => { 'total' => 0, 'worklogs' => [] }
      }

      file_system.when_loading(file: issue_path, json: original_issue)
      file_system.when_saving(file: issue_path)

      # First page with more data
      jira_gateway.when(
        url: '/rest/api/2/issue/TEST-1/worklog?startAt=0&maxResults=100',
        response: {
          'total' => 150,
          'startAt' => 0,
          'maxResults' => 100,
          'worklogs' => (1..100).map { |i| { 'id' => i.to_s, 'timeSpentSeconds' => 3600 * i } }
        }
      )

      # Second page with remaining data
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

      # Verify all 150 worklogs were fetched
      saved_issue = file_system.saved_json[issue_path]
      expect(saved_issue['worklog']['total']).to eq(150)
      expect(saved_issue['worklog']['worklogs'].size).to eq(150)
    end

    it 'handles issues with no worklogs' do
      issue_path = 'spec/testdata/TEST-2-1.json'
      original_issue = {
        'key' => 'TEST-2',
        'id' => '124',
        'fields' => { 'summary' => 'Test' }
      }

      file_system.when_loading(file: issue_path, json: original_issue)
      file_system.when_saving(file: issue_path)

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

      saved_issue = file_system.saved_json[issue_path]
      expect(saved_issue['worklog']['total']).to eq(0)
      expect(saved_issue['worklog']['worklogs']).to be_empty
    end
  end
end
