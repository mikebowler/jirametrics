# frozen_string_literal: true

require './spec/spec_helper'

TARGET_PATH = 'spec/tmp/testdir'

describe Exporter do
  let(:file_system) do
    MockFileSystem.new.tap do |fs|
      fs.when_loading file: 'spec/testdata/jira-config.json', json: :not_mocked
    end
  end
  let(:exporter) { described_class.new file_system: file_system }

  describe '.configure' do
    it 'prints a friendly error and exits when the log file cannot be written' do
      allow(File).to receive(:open).with('jirametrics.log', 'w').and_raise(Errno::EACCES)
      expect { described_class.configure { nil } }
        .to output(/Cannot write to.*jirametrics\.log/).to_stderr
        .and raise_error(SystemExit)
    end
  end

  describe '#target_path' do
    it 'works with no file separator at end' do
      Dir.rmdir TARGET_PATH if File.exist? TARGET_PATH
      exporter.target_path TARGET_PATH
      aggregate_failures do
        expect(exporter.target_path).to eq "#{TARGET_PATH}/"
        expect(Dir).to exist(TARGET_PATH)
      end
    end

    it 'works with file separator at end' do
      Dir.rmdir TARGET_PATH if File.exist? TARGET_PATH
      exporter.target_path "#{TARGET_PATH}/"
      aggregate_failures do
        expect(exporter.target_path).to eq "#{TARGET_PATH}/"
        expect(Dir).to exist(TARGET_PATH)
      end
    end
  end

  describe '#jira_config' do
    it 'raises exception if file not found' do
      expect { exporter.jira_config 'not-found.json' }.to raise_error(
        'Unable to load Jira configuration file and cannot continue: "not-found.json"'
      )
      expect(exporter.file_system.log_messages).to be_empty
    end

    it 'loads config' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      expect(exporter.jira_config['url']).to eq 'https://improvingflow.atlassian.net'
    end

    it 'strips trailing slash from url' do
      exporter.file_system = MockFileSystem.new
      exporter.file_system.when_loading file: 'jira-config.json', json: { 'url' => 'foo/' }
      exporter.jira_config 'jira-config.json'
      expect(exporter.jira_config['url']).to eq 'foo'
    end
  end

  describe '#project' do
    it 'has jira_config set' do
      exporter.target_path TARGET_PATH
      expect { exporter.project }.to raise_error 'jira_config not set'
    end

    it 'creates project_config' do
      exporter.target_path TARGET_PATH
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.project
      expect(exporter.project_configs.collect(&:target_path)).to eq ['spec/tmp/testdir/']
    end
  end

  describe '#holiday_dates' do
    it 'allows simple dates' do
      expect(exporter.holiday_dates '2022-02-03').to eq([Date.parse('2022-02-03')])
    end

    it 'allows ranges' do
      expect(exporter.holiday_dates '2022-12-24..2022-12-26').to eq(
        [Date.parse('2022-12-24'), Date.parse('2022-12-25'), Date.parse('2022-12-26')]
      )
    end

    it 'initializes dates correctly' do
      # This seems like a wierd thing to test for but it was causing exceptions at one point
      expect(exporter.holiday_dates).to be_empty
    end
  end

  describe '#each_project_config' do
    it 'matches all projects' do
      exporter.file_system.when_loading file: 'jira-config.json', json: {}
      exporter.jira_config 'jira-config.json'

      exporter.project name: 'action'
      exporter.project name: 'burrow'
      actual = []
      exporter.each_project_config name_filter: '*' do |project|
        actual << project.name
      end
      expect(actual).to eq %w[action burrow]
    end

    it 'filters by project name' do
      exporter.file_system.when_loading file: 'jira-config.json', json: {}
      exporter.jira_config 'jira-config.json'

      exporter.project name: 'action'
      exporter.project name: 'burrow'
      actual = []
      exporter.each_project_config name_filter: 'a*' do |project|
        actual << project.name
      end
      expect(actual).to eq %w[action]
    end
  end

  describe '#download' do
    it 'fails if download block is missing' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.project name: 'foo'
      expect { exporter.download name_filter: '*' }.to raise_error(
        'Project "foo" is missing a download section in the config. That is required in order to download'
      )
    end
  end

  describe '#verify_jira_connections' do
    let(:ok_result) do
      JiraGateway::VerifyResult.new(
        ok: true, url: 'https://acme.atlassian.net',
        message: 'Verified https://acme.atlassian.net — authenticated as Bugs Bunny'
      )
    end
    let(:fail_result) do
      JiraGateway::VerifyResult.new(
        ok: false, url: 'https://acme.atlassian.net',
        message: 'Could not authenticate to https://acme.atlassian.net — token expired'
      )
    end

    it 'returns a passing result and reports the authenticated user when the connection verifies' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.project name: 'foo'
      allow(JiraGateway).to receive(:new).and_return(instance_double(JiraGateway, verify_connection: ok_result))
      results = exporter.verify_jira_connections(name_filter: '*')
      aggregate_failures do
        expect(results.map(&:ok)).to eq [true]
        expect(file_system.log_messages).to include(
          'Verified https://acme.atlassian.net — authenticated as Bugs Bunny'
        )
      end
    end

    it 'returns a failing result and reports the reason when a connection fails to authenticate' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.project name: 'foo'
      allow(JiraGateway).to receive(:new).and_return(instance_double(JiraGateway, verify_connection: fail_result))
      results = exporter.verify_jira_connections(name_filter: '*')
      aggregate_failures do
        expect(results.map(&:ok)).to eq [false]
        expect(file_system.log_messages).to include(
          'Could not authenticate to https://acme.atlassian.net — token expired'
        )
      end
    end

    it 'verifies each distinct Jira URL only once' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.project name: 'foo'
      exporter.project name: 'bar'
      allow(JiraGateway).to receive(:new).and_return(instance_double(JiraGateway, verify_connection: ok_result))
      exporter.verify_jira_connections(name_filter: '*')
      expect(JiraGateway).to have_received(:new).once
    end

    it 'authenticates without requiring a prior download' do
      # Regression: verify is meant to run before the first download, to catch bad credentials
      # early. Evaluating a real standard_project block forces an issue-data load that does not
      # exist yet, which used to crash verify with "No data found. Must do a download...".
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.standard_project name: 'Sample', file_prefix: 'sample', boards: { 2 => :default }
      allow(JiraGateway).to receive(:new).and_return(instance_double(JiraGateway, verify_connection: ok_result))
      expect(exporter.verify_jira_connections(name_filter: '*').map(&:ok)).to eq [true]
    end

    it 'verifies the top-level jira_config when no project is declared yet' do
      # Lets verify run as a first setup step, on just credentials, before any project exists.
      exporter.jira_config 'spec/testdata/jira-config.json'
      allow(JiraGateway).to receive(:new).and_return(instance_double(JiraGateway, verify_connection: ok_result))
      results = exporter.verify_jira_connections(name_filter: '*')
      aggregate_failures do
        expect(results.map(&:ok)).to eq [true]
        expect(JiraGateway).to have_received(:new).once
      end
    end

    it 'reports and returns nothing when no Jira connection is configured' do
      aggregate_failures do
        expect(exporter.verify_jira_connections(name_filter: '*')).to eq []
        expect(file_system.log_messages).to include(
          'Error: No Jira connection found in the configuration to verify'
        )
      end
    end
  end

  describe '#boards' do
    let(:statuses_json) { JSON.parse(File.read('spec/complete_sample/sample_statuses.json')) }
    let(:board_config_json) { JSON.parse(File.read('spec/complete_sample/sample_board_1_configuration.json')) }
    let(:gateway) do
      instance_double(JiraGateway).tap do |gw|
        allow(gw).to receive(:call_url).with(relative_url: '/rest/api/2/status').and_return(statuses_json)
        allow(gw).to receive(:call_url)
          .with(relative_url: '/rest/agile/1.0/board/1/configuration').and_return(board_config_json)
      end
    end

    before do
      exporter.jira_config 'spec/testdata/jira-config.json'
      allow(JiraGateway).to receive(:new).and_return(gateway)
    end

    it 'lists each visible column with its statuses shown as "name":id and category' do
      exporter.boards board_id: '1'
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('"SP board" (kanban)')
        expect(output).to include('Ready')
        expect(output).to include('"Selected for Development":10001 — In Progress')
        expect(output).to include('"Done":10002 — Done')
      end
    end

    it 'marks the kanban backlog statuses as not started' do
      exporter.boards board_id: '1'
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('"Backlog":10000 — To Do')
        expect(output).to match(/not started/i)
      end
    end

    it 'includes a cycletime hint expressed in column names' do
      exporter.boards board_id: '1'
      expect(file_system.log_messages.join("\n")).to include(
        'start_at first_time_in_or_right_of_column'
      )
    end

    it 'lists the accessible boards with id, name and type when no board id is given' do
      allow(gateway).to receive(:call_url)
        .with(relative_url: '/rest/agile/1.0/board?startAt=0&maxResults=50')
        .and_return({
          'isLast' => true,
          'values' => [
            { 'id' => 1, 'name' => 'SP board', 'type' => 'kanban' },
            { 'id' => 2, 'name' => 'Scrum board', 'type' => 'scrum' }
          ]
        })
      exporter.boards board_id: nil
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('1 — "SP board" (kanban)')
        expect(output).to include('2 — "Scrum board" (scrum)')
      end
    end

    it 'follows pagination until the last page' do
      allow(gateway).to receive(:call_url)
        .with(relative_url: '/rest/agile/1.0/board?startAt=0&maxResults=50')
        .and_return({ 'isLast' => false, 'values' => [{ 'id' => 1, 'name' => 'A', 'type' => 'kanban' }] })
      allow(gateway).to receive(:call_url)
        .with(relative_url: '/rest/agile/1.0/board?startAt=1&maxResults=50')
        .and_return({ 'isLast' => true, 'values' => [{ 'id' => 2, 'name' => 'B', 'type' => 'scrum' }] })
      exporter.boards board_id: nil
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('1 — "A" (kanban)')
        expect(output).to include('2 — "B" (scrum)')
      end
    end

    it 'reports when no boards are accessible' do
      allow(gateway).to receive(:call_url)
        .with(relative_url: '/rest/agile/1.0/board?startAt=0&maxResults=50')
        .and_return({ 'isLast' => true, 'values' => [] })
      exporter.boards board_id: nil
      expect(file_system.log_messages.join("\n")).to match(/no boards/i)
    end
  end

  describe '#info' do
    it 'does not match on any issue' do
      exporter.info 'SP-1', name_filter: '*'
      expect(file_system.log_messages).to match_strings([
        'No issues found to match "SP-1"'
      ])
    end
  end

  describe '#filter_issues' do
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue 'SP-1', board: board }
    let(:issue2) { load_issue 'SP-2', board: board }

    it 'does not filter when ignore_issues is nil' do
      issues = [issue1, issue2]
      exporter.filter_issues issues, nil
      expect(issues).to eq [issue1, issue2]
    end

    it 'filters by array of keys' do
      issues = [issue1, issue2]
      exporter.filter_issues issues, ['SP-1']
      expect(issues).to eq [issue2]
    end

    it 'filters by lambda returning true to ignore' do
      issues = [issue1, issue2]
      exporter.filter_issues issues, ->(issue) { issue.key == 'SP-1' }
      expect(issues).to eq [issue2]
    end

    it 'passes the issue to the lambda' do
      received = []
      issues = [issue1, issue2]
      recorder = lambda do |issue|
        received << issue
        false # never ignore, just record
      end
      exporter.filter_issues issues, recorder
      expect(received).to eq [issue1, issue2]
    end
  end
end
