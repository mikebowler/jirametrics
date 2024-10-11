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
  project.status_category_mapping status: 'Backlog', category: 'ready'
  project.status_category_mapping status: 'Selected for Development', category: 'ready'
  project.status_category_mapping status: 'In Progress', category: 'in-flight'
  project.status_category_mapping status: 'Review', category: 'in-flight'
  project.status_category_mapping status: 'Done', category: 'finished'

  DownloadConfig.new project_config: project, block: nil
end

describe Downloader do
  let(:download_config) { mock_download_config }
  let(:file_system) { MockFileSystem.new }
  let(:jira_gateway) { MockJiraGateway.new(file_system: file_system) }
  let(:downloader) do
    described_class.new(download_config: download_config, file_system: file_system, jira_gateway: jira_gateway)
      .tap do |d|
        d.init_gateway
      end
  end

  context 'run' do
    it 'skips the download when no-download specified' do
      file_system.when_loading file: 'spec/testdata/sample_meta.json', json: { 'no-download' => true }
      downloader.run
      expect(file_system.log_messages).to include 'Skipping download. Found no-download in meta file'
    end
  end

  context 'make_jql' do
    it 'only pull deltas if we have a previous download' do
      downloader.metadata.clear
      downloader.metadata['date_end'] = Date.parse('2021-07-20')

      download_config.rolling_date_count 90
      today = Time.parse('2021-08-01')
      expected = 'filter=5 AND (updated >= "2021-07-20 00:00" OR ' \
        '((status changed OR Sprint is not EMPTY) AND statusCategory != Done))'
      expect(downloader.make_jql(today: today, filter_id: 5)).to eql expected

      expect(downloader.start_date_in_query).to eq Date.parse('2021-07-20')
    end

    context 'with dates' do
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
        'Downloading primary issues for board 2',
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
end
