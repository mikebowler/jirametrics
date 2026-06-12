# frozen_string_literal: true

require './spec/spec_helper'
require './spec/mock_file_system'
require './spec/mock_jira_gateway'

describe 'Worklog' do
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

    it 'skips issues whose worklogs are already complete' do
      issue_jsons = [
        { 'id' => '1', 'key' => 'TEST-1', 'fields' => { 'worklog' => { 'total' => 2, 'worklogs' => [{ 'id' => '100' }, { 'id' => '101' }] } } }
      ]

      downloader.attach_worklogs_to_issues(issue_datas: [], issue_jsons: issue_jsons)

      expect(issue_jsons[0]['fields']['worklog']['total']).to eq(2)
      expect(issue_jsons[0]['fields']['worklog']['worklogs'].size).to eq(2)
    end

    it 'fetches remaining worklogs when initial fetch is incomplete' do
      issue_jsons = [
        {
          'id' => '1', 'key' => 'TEST-1',
          'fields' => {
            'worklog' => {
              'total' => 3,
              'worklogs' => [{ 'id' => '100', 'timeSpentSeconds' => 3600 }]
            }
          }
        }
      ]

      jira_gateway.when(
        url: '/rest/api/3/issue/TEST-1/worklog?startAt=1&maxResults=100',
        response: {
          'total' => 3,
          'worklogs' => [
            { 'id' => '101', 'timeSpentSeconds' => 1800 },
            { 'id' => '102', 'timeSpentSeconds' => 900 }
          ]
        }
      )

      downloader.attach_worklogs_to_issues(issue_datas: [], issue_jsons: issue_jsons)

      worklog = issue_jsons[0]['fields']['worklog']
      expect(worklog['total']).to eq(3)
      expect(worklog['worklogs'].size).to eq(3)
      expect(worklog['worklogs'].map { |w| w['id'] }).to eq(%w[100 101 102])
    end

    it 'paginates until all worklogs are fetched' do
      issue_jsons = [
        {
          'id' => '1', 'key' => 'TEST-1',
          'fields' => { 'worklog' => { 'total' => 250, 'worklogs' => [] } }
        }
      ]

      jira_gateway.when(
        url: '/rest/api/3/issue/TEST-1/worklog?startAt=0&maxResults=100',
        response: { 'total' => 250, 'worklogs' => (1..100).map { |i| { 'id' => i.to_s } } }
      )
      jira_gateway.when(
        url: '/rest/api/3/issue/TEST-1/worklog?startAt=100&maxResults=100',
        response: { 'total' => 250, 'worklogs' => (101..200).map { |i| { 'id' => i.to_s } } }
      )
      jira_gateway.when(
        url: '/rest/api/3/issue/TEST-1/worklog?startAt=200&maxResults=100',
        response: { 'total' => 250, 'worklogs' => (201..250).map { |i| { 'id' => i.to_s } } }
      )

      downloader.attach_worklogs_to_issues(issue_datas: [], issue_jsons: issue_jsons)

      worklog = issue_jsons[0]['fields']['worklog']
      expect(worklog['total']).to eq(250)
      expect(worklog['worklogs'].size).to eq(250)
    end

    it 'skips issues with no worklog field' do
      issue_jsons = [{ 'id' => '1', 'key' => 'TEST-1', 'fields' => {} }]

      downloader.attach_worklogs_to_issues(issue_datas: [], issue_jsons: issue_jsons)

      expect(issue_jsons[0]['fields']['worklog']).to be_nil
    end

    it 'skips issues with zero total worklogs' do
      issue_jsons = [
        { 'id' => '1', 'key' => 'TEST-1', 'fields' => { 'worklog' => { 'total' => 0, 'worklogs' => [] } } }
      ]

      downloader.attach_worklogs_to_issues(issue_datas: [], issue_jsons: issue_jsons)

      expect(issue_jsons[0]['fields']['worklog']['total']).to eq(0)
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
      expect(saved_issue['fields']['worklog']['total']).to eq(150)
      expect(saved_issue['fields']['worklog']['worklogs'].size).to eq(150)
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
      expect(saved_issue['fields']['worklog']['total']).to eq(0)
      expect(saved_issue['fields']['worklog']['worklogs']).to be_empty
    end
  end
end
