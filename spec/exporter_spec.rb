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
    after { described_class.logfile_name = 'jirametrics.log' }

    it 'prints a friendly error and exits when the log file cannot be written' do
      allow(File).to receive(:open).with('jirametrics.log', 'w').and_raise(Errno::EACCES)
      expect { described_class.configure { nil } }
        .to output(/Cannot write to.*jirametrics\.log/).to_stderr
        .and raise_error(SystemExit)
    end

    it 'opens the log file named by logfile_name, so the MCP server can use its own' do
      described_class.logfile_name = 'jirametrics-mcp.log'
      allow(File).to receive(:open).with('jirametrics-mcp.log', 'w').and_raise(Errno::EACCES)
      expect { described_class.configure { nil } }
        .to output(/Cannot write to.*jirametrics-mcp\.log/).to_stderr
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

  # A config may switch target directories partway through, which is how an issue ends up
  # downloaded into one directory and searched for in another. See GitHub issue 77.
  describe '#target_path logging' do
    it 'records the first one it is given' do
      exporter.target_path TARGET_PATH
      expect(file_system.log_messages.join("\n")).to include 'target_path set to "spec/tmp/testdir/"'
    end

    it 'records a change, naming both the old and the new' do
      exporter.target_path TARGET_PATH
      exporter.target_path 'spec/tmp/elsewhere'
      expect(file_system.log_messages.join("\n"))
        .to include 'target_path changed from "spec/tmp/testdir/" to "spec/tmp/elsewhere/"'
    end

    # A config that sets the same path twice has not changed anything, and reporting a change
    # would send someone hunting for a switch that never happened.
    it 'says nothing when the path is set again to the same value' do
      exporter.target_path TARGET_PATH
      before = file_system.log_messages.size
      exporter.target_path TARGET_PATH
      expect(file_system.log_messages.size).to eq before
    end

    it 'says nothing when only reading the value' do
      exporter.target_path TARGET_PATH
      before = file_system.log_messages.size
      exporter.target_path
      expect(file_system.log_messages.size).to eq before
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
        message: 'Verified https://acme.atlassian.net (authenticated as Bugs Bunny)'
      )
    end
    let(:fail_result) do
      JiraGateway::VerifyResult.new(
        ok: false, url: 'https://acme.atlassian.net',
        message: 'Could not authenticate to https://acme.atlassian.net: token expired'
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
          'Verified https://acme.atlassian.net (authenticated as Bugs Bunny)'
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
          'Could not authenticate to https://acme.atlassian.net: token expired'
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
    let(:minimal_statuses) do
      [
        { 'id' => '1', 'name' => 'To Do',
          'statusCategory' => { 'id' => 2, 'name' => 'To Do', 'key' => 'new' } },
        { 'id' => '2', 'name' => 'In Progress',
          'statusCategory' => { 'id' => 4, 'name' => 'In Progress', 'key' => 'indeterminate' } },
        { 'id' => '3', 'name' => 'Done',
          'statusCategory' => { 'id' => 3, 'name' => 'Done', 'key' => 'done' } }
      ]
    end

    before do
      exporter.jira_config 'spec/testdata/jira-config.json'
      allow(JiraGateway).to receive(:new).and_return(gateway)
    end

    def minimal_board_config type:
      {
        'name' => 'Test board', 'type' => type,
        'columnConfig' => { 'columns' => [
          { 'name' => 'To Do', 'statuses' => [{ 'id' => '1' }] },
          { 'name' => 'In Progress', 'statuses' => [{ 'id' => '2' }] },
          { 'name' => 'Done', 'statuses' => [{ 'id' => '3' }] }
        ] }
      }
    end

    # Wire a gateway that serves one board of the given type (and, for team-managed boards, a
    # features response saying whether sprints are enabled).
    def stub_board type:, sprints: nil
      gw = instance_double(JiraGateway)
      allow(gw).to receive(:call_url).with(relative_url: '/rest/api/2/status').and_return(minimal_statuses)
      allow(gw).to receive(:call_url)
        .with(relative_url: '/rest/agile/1.0/board/9/configuration').and_return(minimal_board_config(type: type))
      unless sprints.nil?
        allow(gw).to receive(:call_url)
          .with(relative_url: '/rest/agile/1.0/board/9/features')
          .and_return({ 'features' => [{ 'feature' => 'jsw.agility.sprints',
                                         'state' => sprints ? 'ENABLED' : 'DISABLED' }] })
      end
      allow(JiraGateway).to receive(:new).and_return(gw)
    end

    it 'lists each visible column with its statuses shown as "name":id and category' do
      exporter.boards board_id: '1'
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('"SP board" (kanban)')
        expect(output).to include('Ready')
        expect(output).to include('"Selected for Development":10001 (In Progress)')
        expect(output).to include('"Done":10002 (Done)')
      end
    end

    it 'marks the kanban backlog statuses as not started' do
      exporter.boards board_id: '1'
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('"Backlog":10000 (To Do)')
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
        expect(output).to include('1: "SP board" (kanban)')
        expect(output).to include('2: "Scrum board" (scrum)')
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
        expect(output).to include('1: "A" (kanban)')
        expect(output).to include('2: "B" (scrum)')
      end
    end

    it 'lists boards sorted by name, case-insensitively' do
      allow(gateway).to receive(:call_url)
        .with(relative_url: '/rest/agile/1.0/board?startAt=0&maxResults=50')
        .and_return({ 'isLast' => true, 'values' => [
          { 'id' => 1, 'name' => 'Zebra', 'type' => 'kanban' },
          { 'id' => 2, 'name' => 'apple', 'type' => 'scrum' },
          { 'id' => 3, 'name' => 'Mango', 'type' => 'simple' }
        ] })
      exporter.boards board_id: nil
      output = file_system.log_messages.join("\n")
      expect(output.index('apple')).to be < output.index('Mango')
      expect(output.index('Mango')).to be < output.index('Zebra')
    end

    it 'filters the board list by a case-insensitive name glob when name_filter is given' do
      allow(gateway).to receive(:call_url)
        .with(relative_url: '/rest/agile/1.0/board?startAt=0&maxResults=50')
        .and_return({ 'isLast' => true, 'values' => [
          { 'id' => 1, 'name' => 'Mobile Squad', 'type' => 'kanban' },
          { 'id' => 2, 'name' => 'Web Squad', 'type' => 'kanban' }
        ] })
      exporter.boards board_id: nil, name_filter: 'mob*'
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('Mobile Squad')
        expect(output).not_to include('Web Squad')
      end
    end

    it 'reports when no boards are accessible' do
      allow(gateway).to receive(:call_url)
        .with(relative_url: '/rest/agile/1.0/board?startAt=0&maxResults=50')
        .and_return({ 'isLast' => true, 'values' => [] })
      exporter.boards board_id: nil
      expect(file_system.log_messages.join("\n")).to match(/no boards/i)
    end

    it 'labels a scrum board and offers sprint-based start' do
      stub_board type: 'scrum'
      exporter.boards board_id: '9'
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('(scrum)')
        expect(output).to include('start_at first_time_added_to_active_sprint')
      end
    end

    it 'resolves a team-managed board that uses sprints and offers sprint-based start' do
      stub_board type: 'simple', sprints: true
      exporter.boards board_id: '9'
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('(team-managed, uses sprints)')
        expect(output).to include('start_at first_time_added_to_active_sprint')
      end
    end

    it 'resolves a team-managed board without sprints and does not offer sprint-based start' do
      stub_board type: 'simple', sprints: false
      exporter.boards board_id: '9'
      output = file_system.log_messages.join("\n")
      aggregate_failures do
        expect(output).to include('(team-managed, no sprints)')
        expect(output).not_to include('first_time_added_to_active_sprint')
      end
    end

    it 'does not offer sprint-based start for a kanban board' do
      stub_board type: 'kanban'
      exporter.boards board_id: '9'
      expect(file_system.log_messages.join("\n")).not_to include('first_time_added_to_active_sprint')
    end

    it 'reports a clean error and returns false when listing boards fails' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      gw = instance_double(JiraGateway)
      allow(gw).to receive(:call_url).and_raise('Failed call with exit status 56. See jirametrics.log for details')
      allow(JiraGateway).to receive(:new).and_return(gw)
      result = exporter.boards board_id: nil
      aggregate_failures do
        expect(result).to be false
        expect(file_system.log_messages.join("\n")).to match(/couldn't list boards/i)
      end
    end

    it 'reports a clean error naming the board and returns false when a board id cannot be read' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      gw = instance_double(JiraGateway)
      allow(gw).to receive(:call_url).and_raise('Failed call with exit status 56. See jirametrics.log for details')
      allow(JiraGateway).to receive(:new).and_return(gw)
      result = exporter.boards board_id: '99999999'
      aggregate_failures do
        expect(result).to be false
        expect(file_system.log_messages.join("\n")).to match(/board 99999999/i)
      end
    end
  end

  describe '#info' do
    it 'does not match on any issue' do
      exporter.info 'SP-1', name_filter: '*'
      # The pair is the terminal line plus the detail that only goes to the log file.
      expect(file_system.log_messages).to match_strings([
        ['No issues found to match "SP-1"',
         'No project configurations were searched at all. Either none are defined in the config ' \
           'file or none of them matched the name filter.']
      ])
    end

    # A config that filters out an issue type, such as ignore_types, leaves that issue nowhere to
    # be found, and info used to report it as missing. Reported in GitHub issue 77, where the
    # reporter spent a day chasing a download problem that was really a filter.
    describe '#matching_issues_in' do
      let(:board) { load_complete_sample_board }
      let(:project) do
        instance_double ProjectConfig, name: 'Sampler', issues: collection
      end
      let(:visible) { load_issue 'SP-1', board: board }
      let(:excluded) { load_issue 'SP-2', board: board }
      let(:collection) do
        c = IssueCollection[visible, excluded]
        c.reject! { |issue| issue.key == 'SP-2' }
        c
      end

      it 'finds an issue that is still in play, and marks it as used' do
        expect(exporter.matching_issues_in(project, 'SP-1')).to eq [[project, visible, false]]
      end

      it 'finds an issue a filter removed, and marks it as ignored' do
        expect(exporter.matching_issues_in(project, 'SP-2')).to eq [[project, excluded, true]]
      end

      it 'still finds nothing for a key that is not there at all' do
        expect(exporter.matching_issues_in(project, 'SP-999')).to be_empty
      end
    end

    # The terminal stays sparse; the detail goes to the log. Without it a user whose issue was
    # downloaded but not found has nothing to go on, which is what happened in GitHub issue 77.
    describe '#describe_search' do
      it 'names the project and the directory its issues came from' do
        project = instance_double(
          ProjectConfig, name: 'Sampler', target_path: 'target/', issues: IssueCollection.new
        )
        12.times { project.issues << 'issue' }
        allow(project).to receive(:get_file_prefix).with(raise_if_not_set: false).and_return('sample')
        expect(exporter.describe_search project: project, matches: 0)
          .to eq '  "Sampler": target/sample_issues (12 issues loaded, 0 matched)'
      end

      it 'says so when no file_prefix has been set, rather than inventing a path' do
        project = instance_double ProjectConfig, name: 'Half built', target_path: 'target/',
          issues: IssueCollection.new
        allow(project).to receive(:get_file_prefix).with(raise_if_not_set: false).and_return(nil)
        expect(exporter.describe_search project: project, matches: 0)
          .to include '(no file_prefix set)'
      end

      # Filtered-out issues are still on disk and still findable, so the count has to distinguish
      # them from issues that were never loaded.
      it 'reports how many issues a filter removed' do
        collection = IssueCollection.new
        %w[a b c].each { |k| collection << k }
        collection.reject! { |issue| issue == 'c' }
        project = instance_double ProjectConfig, name: 'Sampler', target_path: 'target/', issues: collection
        allow(project).to receive(:get_file_prefix).with(raise_if_not_set: false).and_return('sample')
        expect(exporter.describe_search project: project, matches: 0)
          .to eq '  "Sampler": target/sample_issues (2 issues loaded, 1 excluded by filters, 0 matched)'
      end

      # A project whose issues cannot be read at all must still appear in the list. Dropping it
      # would leave the user wondering whether it was searched.
      it 'still reports a project whose issues could not be read' do
        project = instance_double ProjectConfig, name: 'Broken', target_path: 'target/'
        allow(project).to receive(:get_file_prefix).with(raise_if_not_set: false).and_return('broken')
        allow(project).to receive(:issues).and_raise('no data found')
        expect(exporter.describe_search project: project, matches: 0)
          .to include 'could not be read'
      end
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
