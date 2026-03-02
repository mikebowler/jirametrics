# frozen_string_literal: true

require './spec/spec_helper'
require './spec/mock_file_system'
require './spec/mock_jira_gateway'

def mock_download_config
  exporter = Exporter.new
  jira_config = {
    'url' => 'https://example.atlassian.com',
    'email' => 'bugs_bunny@example.com',
    'api_token' => 'carrots'
  }
  project = ProjectConfig.new(
    exporter: exporter, target_path: 'spec/testdata/', jira_config: jira_config, block: nil
  )
  project.file_prefix 'sample'

  DownloadConfig.new project_config: project, block: nil
end

describe DownloaderForCloud do
  let(:download_config) { mock_download_config }
  let(:file_system) { MockFileSystem.new }
  let(:jira_gateway) do
    MockJiraGateway.new(
      file_system: file_system,
      jira_config: download_config.project_config.jira_config,
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
    it 'defaults to cloud for atlassian domains' do
      jira_gateway = MockJiraGateway.new(
        file_system: file_system,
        jira_config: { 'url' => 'https://example.atlassian.net' },
        settings: { 'ignore_ssl_errors' => false }
      )
      instance = Downloader.create(
        download_config: download_config,
        file_system: file_system,
        jira_gateway: jira_gateway
      )
      expect(instance).to be_instance_of described_class
    end

    it 'picks cloud when declared in settings' do
      jira_gateway = MockJiraGateway.new(
        file_system: file_system,
        jira_config: { 'url' => 'https://example.com' },
        settings: { 'ignore_ssl_errors' => false, 'jira_cloud' => true }
      )
      instance = Downloader.create(
        download_config: download_config,
        file_system: file_system,
        jira_gateway: jira_gateway
      )
      expect(instance).to be_instance_of described_class
    end
  end

  context 'run' do
    it 'skips the download when no-download specified' do
      file_system.when_loading file: 'spec/testdata/sample_meta.json', json: { 'no-download' => true }
      downloader.run
      expect(file_system.log_messages).to include 'Skipping download. Found no-download in meta file'
    end
  end

  context 'load_metadata' do
    it 'forces a full download when rolling_date_count has changed' do
      file_system.when_loading(
        file: 'spec/testdata/sample_meta.json',
        json: {
          'version' => Downloader::CURRENT_METADATA_VERSION,
          'rolling_date_count' => 90,
          'date_end' => '2021-08-01'
        }
      )
      download_config.rolling_date_count 60

      downloader.load_metadata

      expect(downloader.metadata['date_end']).to be_nil
      expect(file_system.log_messages).to include 'rolling_date_count has changed. Forcing a full download.'
    end

    it 'does not force a full download when rolling_date_count is unchanged' do
      file_system.when_loading(
        file: 'spec/testdata/sample_meta.json',
        json: {
          'version' => Downloader::CURRENT_METADATA_VERSION,
          'rolling_date_count' => 90,
          'date_end' => '2021-08-01'
        }
      )
      download_config.rolling_date_count 90

      downloader.load_metadata

      expect(downloader.metadata['date_end']).to eq(Date.parse('2021-08-01'))
    end

    it 'does not force a full download when neither old nor new config has rolling_date_count' do
      file_system.when_loading(
        file: 'spec/testdata/sample_meta.json',
        json: {
          'version' => Downloader::CURRENT_METADATA_VERSION,
          'date_end' => '2021-08-01'
        }
      )

      downloader.load_metadata

      expect(downloader.metadata['date_end']).to eq(Date.parse('2021-08-01'))
    end
  end

  context 'extract_project_keys_from_downloaded_issues' do
    it 'returns project keys from issue filenames' do
      file_system.when_dir_exists? path: 'spec/testdata/sample_issues', result: true
      file_system.when_foreach root: 'spec/testdata/sample_issues', result: %w[SP-1-1.json SP-2-1.json OTHER-10-1.json]

      expect(downloader.extract_project_keys_from_downloaded_issues).to match_array %w[SP OTHER]
    end

    it 'returns empty when the issues directory does not exist' do
      file_system.when_dir_exists? path: 'spec/testdata/sample_issues', result: false

      expect(downloader.extract_project_keys_from_downloaded_issues).to be_empty
    end

    it 'ignores non-issue files in the directory' do
      file_system.when_dir_exists? path: 'spec/testdata/sample_issues', result: true
      file_system.when_foreach root: 'spec/testdata/sample_issues',
                               result: %w[SP-1-1.json .gitkeep some_other_file.json]

      expect(downloader.extract_project_keys_from_downloaded_issues).to eq ['SP']
    end
  end

  context 'download_github_prs' do
    it 'skips download when no project keys are found' do
      file_system.when_dir_exists? path: 'spec/testdata/sample_issues', result: true
      file_system.when_foreach root: 'spec/testdata/sample_issues', result: []

      download_config.github_repo 'owner/repo'
      downloader.download_github_prs

      expect(file_system.saved_json).not_to have_key 'spec/testdata/sample_github_prs.json'
      expect(file_system.log_messages).to include 'No project keys found in downloaded issues, skipping GitHub PR download'
    end

    it 'collects PRs from multiple repos and saves them' do
      file_system.when_dir_exists? path: 'spec/testdata/sample_issues', result: true
      file_system.when_foreach root: 'spec/testdata/sample_issues', result: ['SP-1-1.json']

      download_config.github_repo 'owner/repo1', 'owner/repo2'

      pr1 = { 'number' => 1, 'repo' => 'owner/repo1', 'issue_keys' => ['SP-1'] }
      pr2 = { 'number' => 2, 'repo' => 'owner/repo2', 'issue_keys' => ['SP-1'] }

      gateway1 = instance_double(GithubGateway, fetch_pull_requests: [pr1])
      gateway2 = instance_double(GithubGateway, fetch_pull_requests: [pr2])

      allow(GithubGateway).to receive(:new).with(hash_including(repo: 'owner/repo1')).and_return(gateway1)
      allow(GithubGateway).to receive(:new).with(hash_including(repo: 'owner/repo2')).and_return(gateway2)

      downloader.download_github_prs

      saved = JSON.parse(file_system.saved_json['spec/testdata/sample_github_prs.json'])
      expect(saved.map { |pr| pr['number'] }).to eq [1, 2]
    end
  end

  context 'make_jql' do
    it 'pulls from all time when rolling_date_count not set' do
      jql = downloader.make_jql(today: Time.parse('2021-08-01'), filter_id: 5)
      expect(jql).to eql 'filter=5'
    end

    it 'pulls from specified date when only no_earlier_than is set' do
      download_config.no_earlier_than '2020-08-15'

      jql = downloader.make_jql(today: Time.parse('2021-08-20'), filter_id: 5)
      expect(jql).to eql 'filter=5 AND (updated >= "2020-08-15 00:00" OR ' \
        '((status changed OR Sprint is not EMPTY) AND statusCategory != Done))'
    end

    it 'pulls only the days specified by rolling_date_count' do
      download_config.rolling_date_count 90

      jql = downloader.make_jql(today: Time.parse('2021-08-01'), filter_id: 5)
      expect(jql).to eql 'filter=5 AND (updated >= "2021-05-03 00:00" OR ' \
        '((status changed OR Sprint is not EMPTY) AND statusCategory != Done))'
    end

    it 'pulls only issues after no_earlier_than when that is later than rolling date count' do
      download_config.rolling_date_count 90
      download_config.no_earlier_than '2021-08-10'

      jql = downloader.make_jql(today: Time.parse('2021-08-20'), filter_id: 5)
      expect(jql).to eql 'filter=5 AND (updated >= "2021-08-10 00:00" OR ' \
        '((status changed OR Sprint is not EMPTY) AND statusCategory != Done))'
    end

    it 'ignores no_earlier_than if it is earlier than the rolling date count' do
      download_config.rolling_date_count 90
      download_config.no_earlier_than '2020-08-10'

      jql = downloader.make_jql(today: Time.parse('2021-08-01'), filter_id: 5)
      expect(jql).to eql 'filter=5 AND (updated >= "2021-05-03 00:00" OR ' \
        '((status changed OR Sprint is not EMPTY) AND statusCategory != Done))'
    end

    it 'uses project timezone to compute today when no today is passed' do
      download_config.project_config.exporter.timezone_offset '+05:30'
      download_config.rolling_date_count 90

      # Freeze time to a specific UTC moment where UTC date != +05:30 date
      # 2021-08-01 20:00:00 UTC = 2021-08-02 01:30:00 +05:30
      allow(Time).to receive(:now).and_return(Time.parse('2021-08-01T20:00:00+00:00'))

      jql = downloader.make_jql(filter_id: 5)
      # today in +05:30 is 2021-08-02, so 90 days back is 2021-05-04
      expect(jql).to include('updated >= "2021-05-04 00:00"')
    end
  end

  context 'download_statuses' do
    it 'loads statuses' do
      jira_gateway.when url: '/rest/api/2/status', response: { 'a' => 1 }

      downloader.download_statuses

      expect(file_system.log_messages).to eq(['Downloading all statuses'])
      expect(file_system.saved_json).to eq({
        'spec/testdata/sample_statuses.json' => '{"a":1}'
      })
    end
  end

  context 'update_status_history_file' do
    it 'does nothing when status file does not exist' do
      downloader.update_status_history_file
      expect(file_system.log_messages).to be_empty
      expect(file_system.saved_json).to be_empty
    end

    it 'copies status to history when history did not exist' do
      json = [{
        'name' => 'Doing',
        'id' => '5',
        'statusCategory' => {
          'id' => '2',
          'name' => 'To Do'
        }
      }]
      file_system.when_loading(file: 'spec/testdata/sample_statuses.json', json: json)

      downloader.update_status_history_file
      expect(file_system.log_messages).to eq([
        'Creating status history file'
      ])
      expect(file_system.saved_json_expanded).to eq({
        'spec/testdata/sample_status_history.json' => json
      })
    end

    it 'merges history' do
      file_system.when_loading(file: 'spec/testdata/sample_status_history.json', json: [
        {
          'name' => 'A', 'id' => '5',
          'statusCategory' => { 'id' => '10', 'name' => 'To Do' }
        },
        {
          'name' => 'B', 'id' => '2',
          'statusCategory' => { 'id' => '10', 'name' => 'To Do' }
        }
      ])

      file_system.when_loading(file: 'spec/testdata/sample_statuses.json', json: [
        {
          'name' => 'B', 'id' => '2',
          'statusCategory' => { 'id' => '11', 'name' => 'Done' }
        },
        {
          'name' => 'C', 'id' => '3',
          'statusCategory' => { 'id' => '10', 'name' => 'To Do' }
        }
      ])

      downloader.update_status_history_file
      expect(file_system.log_messages).to eq([
        'Updating status history file'
      ])
      expect(file_system.saved_json_expanded).to eq({
        'spec/testdata/sample_status_history.json' => [
          {
            'name' => 'A', 'id' => '5',
            'statusCategory' => { 'id' => '10', 'name' => 'To Do' }
          },
          {
            'name' => 'B', 'id' => '2',
            'statusCategory' => { 'id' => '11', 'name' => 'Done' }
          },
          {
            'name' => 'C', 'id' => '3',
            'statusCategory' => { 'id' => '10', 'name' => 'To Do' }
          }
        ]
      })
    end
  end

  context 'download_board_configuration' do
    it 'suceeds for kanban board' do
      configuration_json = {
        'id' => '2',
        'filter' => { 'id' => 1 },
        'type' => 'kanban',
        'columnConfig' => {
          'columns' => [
            # A kanban board will always have a first column
            {
              'name' => 'Backlog',
              'statuses' => [
                {
                  'id' => '10000'
                }
              ]
            }
          ]
        },
        'statuses' => []
      }
      url = '/rest/agile/1.0/board/2/configuration'
      jira_gateway.when url: url, response: configuration_json

      downloader.download_board_configuration board_id: 2

      expect(file_system.log_messages).to eq(['Downloading board configuration for board 2'])
      expect(file_system.saved_json).to eq({
        'spec/testdata/sample_board_2_configuration.json' => JSON.generate(configuration_json)
      })
    end

    it 'pulls extra data for scrum board' do
      configuration_json = {
        'id' => '2',
        'filter' => { 'id' => 1 },
        'type' => 'scrum',
        'columnConfig' => { 'columns' => [] }
      }
      jira_gateway.when(
        url: '/rest/agile/1.0/board/2/configuration',
        response: configuration_json
      )

      sprints_json = { 'isLast' => true, 'maxResults' => 100, 'values' => 1 }
      jira_gateway.when(
        url: '/rest/agile/1.0/board/2/sprint?maxResults=100&startAt=0',
        response: sprints_json
      )

      downloader.download_board_configuration board_id: 2

      expect(file_system.log_messages).to eq([
        'Downloading board configuration for board 2',
        'Downloading sprints for board 2'
      ])
      expect(file_system.saved_json).to eq({
        'spec/testdata/sample_board_2_configuration.json' => JSON.generate(configuration_json),
        'spec/testdata/sample_board_2_sprints_0.json' => JSON.generate(sprints_json)
      })
    end

    it 'pulls extra data for scrum board with pagination' do
      configuration_json = {
        'id' => '2',
        'filter' => { 'id' => 1 },
        'type' => 'scrum',
        'columnConfig' => { 'columns' => [] }
      }
      jira_gateway.when(
        url: '/rest/agile/1.0/board/2/configuration',
        response: configuration_json
      )
      jira_gateway.when(
        url: '/rest/agile/1.0/board/2/sprint?maxResults=100&startAt=0',
        response: { 'isLast' => false, 'maxResults' => 1, 'values' => [{ 'a' => 2 }] }
      )
      jira_gateway.when(
        url: '/rest/agile/1.0/board/2/sprint?maxResults=1&startAt=1',
        response: { 'isLast' => true, 'maxResults' => 1, 'values' => [{ 'a' => 2 }] }
      )

      downloader.download_board_configuration board_id: 2

      expect(file_system.log_messages).to eq([
        'Downloading board configuration for board 2',
        'Downloading sprints for board 2'
      ])
      expect(file_system.saved_json).to eq({
        'spec/testdata/sample_board_2_configuration.json' => JSON.generate(configuration_json),
        'spec/testdata/sample_board_2_sprints_0.json' => '{"isLast":false,"maxResults":1,"values":[{"a":2}]}',
        'spec/testdata/sample_board_2_sprints_1.json' => '{"isLast":true,"maxResults":1,"values":[{"a":2}]}'
      })
    end

    it 'does not blow up for a board with no sprints' do
      configuration_json = {
        'id' => '2',
        'filter' => { 'id' => 1 },
        'type' => 'scrum',
        'columnConfig' => { 'columns' => [] }
      }
      jira_gateway.when(
        url: '/rest/agile/1.0/board/2/configuration',
        response: configuration_json
      )
      jira_gateway.when(
        url: '/rest/agile/1.0/board/2/sprint?maxResults=100&startAt=0',
        response: { 'isLast' => true, 'maxResults' => 1, 'values' => nil }
      )

      downloader.download_board_configuration board_id: 2

      expect(file_system.log_messages).to eq([
        'Downloading board configuration for board 2',
        'Downloading sprints for board 2',
        'No sprints found for board 2'
      ])
    end
  end

  context 'download_issues' do
    it 'finds no issues' do
      allow(downloader).to(receive(:search_for_issues)).and_return({})

      file_system.when_foreach root: 'spec/testdata/sample_issues/', result: []

      board = sample_board
      board.raw['id'] = 2
      downloader.board_id_to_filter_id[2] = 123
      downloader.download_issues board: board

      expect(file_system.log_messages).to eq([
        'Downloading primary issues for board 2 from Jira Cloud',
        'Creating path spec/testdata/sample_issues/',
        '[Debug] mkdir spec/testdata/sample_issues/'
      ])
      expect(file_system.saved_json).to be_empty
    end

    it 'finds one issue that is not in cache' do
      board = sample_board
      board.raw['id'] = 2
      downloader.board_id_to_filter_id[2] = 123

      issue = empty_issue(
        key: 'ABC-123', created: '2025-01-01', board: board
      )
      allow(downloader).to receive(:search_for_issues) do
        {
          'ABC-123' => DownloadIssueData.new(key: 'ABC-123', up_to_date: false),
          'ABC-456' => DownloadIssueData.new(key: 'ABC-456', up_to_date: true)
        }
      end
      allow(downloader).to receive(:bulk_fetch_issues) do
        [
          DownloadIssueData.new(
            key: 'ABC-123', up_to_date: false, cache_path: 'foo.json', issue: issue
          )
        ]
      end

      file_system.when_foreach root: 'spec/testdata/sample_issues/', result: []

      downloader.download_issues board: board
      expect(file_system.log_messages).to eq([
        'Downloading primary issues for board 2 from Jira Cloud',
        'Creating path spec/testdata/sample_issues/',
        '[Debug] mkdir spec/testdata/sample_issues/',
        '[Debug] utime 2025-01-01 00:00:00 +0000 foo.json'
      ])
      expect(file_system.saved_json).to eq({
        'foo.json' => JSON.generate(issue.raw)
      })
    end
  end

  context 'bulk_fetch_issues' do
    let(:raw_issue) do
      raw_issue = empty_issue(created: '2025-01-01').raw
      raw_issue['changelog'] = nil
      raw_issue['id'] = '123'
      raw_issue
    end
    let(:changelog_response) do
      {
        'issueChangeLogs' => [
          {
            'issueId' => raw_issue['id'],
            'changeHistories' => [
              {
                'id' => '11813',
                'author' => {
                  'emailAddress' => 'mike@example.com',
                  'avatarUrls' => {
                    '16x16' => 'https://example.com'
                  },
                  'displayName' => 'Mike Bowler',
                  'active' => true
                },
                'created' => 1_759_080_993_142,
                'items' => [
                  {
                    'field' => 'status',
                    'fieldId' => 'status',
                    'from' => '1',
                    'fromString' => 'Ready',
                    'to' => '2',
                    'toString' => 'Review'
                  }
                ]
              }
            ]
          }
        ]
      }
    end

    it 'fetches' do
      raw_issue = empty_issue(created: '2025-01-01').raw
      raw_issue['changelog'] = nil
      raw_issue['id'] = '123'

      jira_gateway.when url: '/rest/api/3/issue/bulkfetch', response: {
        'issues' => [raw_issue]
      }
      jira_gateway.when url: '/rest/api/3/changelog/bulkfetch', response: changelog_response

      issue_data1 = DownloadIssueData.new key: 'SP-1', cache_path: 'SP-1.json'
      downloader.bulk_fetch_issues(
        issue_datas: [issue_data1], board: sample_board, in_initial_query: true
      )
      expect(file_system.log_messages).to eq([
        'Downloading 1 issues',
        'post_request: relative_url=/rest/api/3/issue/bulkfetch, ' \
          'payload={"fields":["*all"],"issueIdsOrKeys":["SP-1"]}',
        'post_request: relative_url=/rest/api/3/changelog/bulkfetch, ' \
          'payload={"issueIdsOrKeys":["SP-1"],"maxResults":10000}'
      ])
      expect(issue_data1.issue.status_changes).to eq([
        mock_change(
          field: 'status',
          value: 'Ready',
          value_id: 1,
          time: '2025-01-01',
          artificial: true
        ),
        mock_change(
          field: 'status',
          value: 'Review',
          value_id: 2,
          old_value: 'Ready',
          old_value_id: 1,
          time: '2025-09-28T17:36:33'
        )
     ])
    end

    it 'fetches with pagination' do
      jira_gateway.when url: '/rest/api/3/issue/bulkfetch', response: {
        'issues' => [raw_issue]
      }
      change_log_response_with_next_page = deep_copy(changelog_response)
      change_log_response_with_next_page['nextPageToken'] = 'ABC'
      change_log_response_with_next_page['issueChangeLogs']
        .first['changeHistories']
        .first['created'] = to_time('2025-09-20').to_s
      jira_gateway.when(url: '/rest/api/3/changelog/bulkfetch', response: [
        change_log_response_with_next_page,
        changelog_response
      ])

      issue_data1 = DownloadIssueData.new key: 'SP-1', cache_path: 'SP-1.json'
      downloader.bulk_fetch_issues(
        issue_datas: [issue_data1], board: sample_board, in_initial_query: true
      )
      expect(file_system.log_messages).to eq([
        'Downloading 1 issues',
        'post_request: relative_url=/rest/api/3/issue/bulkfetch, ' \
          'payload={"fields":["*all"],"issueIdsOrKeys":["SP-1"]}',
        'post_request: relative_url=/rest/api/3/changelog/bulkfetch, ' \
          'payload={"issueIdsOrKeys":["SP-1"],"maxResults":10000}',
        'post_request: relative_url=/rest/api/3/changelog/bulkfetch, ' \
          'payload={"issueIdsOrKeys":["SP-1"],"maxResults":10000,"nextPageToken":"ABC"}'
      ])

      expect(issue_data1.issue.status_changes).to eq([
        mock_change(
          field: 'status',
          value: 'Ready',
          value_id: 1,
          time: '2025-01-01',
          artificial: true
        ),
        mock_change(
          field: 'status',
          value: 'Review',
          value_id: 2,
          old_value: 'Ready',
          old_value_id: 1,
          time: '2025-09-20T00:00:00'
        ),
        mock_change(
          field: 'status',
          value: 'Review',
          value_id: 2,
          old_value: 'Ready',
          old_value_id: 1,
          time: '2025-09-28T17:36:33'
        )
     ])
    end
  end
end
