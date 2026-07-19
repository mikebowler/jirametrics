# frozen_string_literal: true

require './spec/spec_helper'

describe ProjectConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:target_path) { 'spec/testdata/' }
  let(:project_config) do
    exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: :not_mocked
    exporter.file_system.when_loading file: 'spec/testdata/sample_statuses.json', json: :not_mocked
    exporter.file_system.when_loading file: 'spec/testdata/sample_board_1_configuration.json', json: :not_mocked
    exporter.file_system.when_foreach root: 'spec/tmp', result: :not_mocked
    exporter.file_system.when_foreach root: 'spec/testdata/sample_issues', result: :not_mocked

    described_class.new(exporter: exporter, target_path: target_path, name: 'one', jira_config: nil, block: nil)
  end
  let(:board) do
    board = sample_board
    board.project_config = project_config
    board
  end
  let(:issue1) { load_issue('SP-1', board: board) }

  describe '#load_all_boards' do
    it 'loads each board with its columns parsed' do
      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      expect(project_config.all_boards.keys).to eq [1]

      contents = project_config.all_boards[1].visible_columns.collect do |column|
        [column.name, column.status_ids, column.min, column.max]
      end

      expect(contents).to eq [
        ['Ready',       [10_001],   1,   4],
        ['In Progress',      [3], nil,   3],
        ['Review',      [10_011], nil,   3],
        ['Done',        [10_002], nil, nil]
      ]
    end
  end

  describe '#possible_statuses' do
    it 'loads' do
      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings

      expected = [
        ['Backlog', 'To Do'],
        ['Done', 'Done'],
        ['FakeBacklog', 'To Do'],
        ['In Progress', 'In Progress'],
        ['Review', 'In Progress'],
        ['Selected for Development', 'In Progress']
      ]

      actual = project_config.possible_statuses.collect do |status|
        [status.name, status.category.name]
      end

      expect(actual.sort).to eq expected.sort
    end
  end

  describe '#download' do
    it 'fails if a second download is set' do
      project_config.download do
        file_suffix 'a'
      end
      expect { project_config.download { file_suffix 'a' } }.to raise_error(
        'Not allowed to have multiple download blocks in one project'
      )
    end
  end

  describe '#evaluate_next_level' do
    it 'executes the original block that had been passed in, in its own context' do
      columns = described_class.new exporter: exporter, target_path: nil, jira_config: nil,
        block: ->(_) { self.class.to_s }
      expect(columns.evaluate_next_level).to eq('ProjectConfig')
    end
  end

  describe '#guess_board_id' do
    it 'fails if no board id set and there are no boards' do
      expect { project_config.guess_board_id }.to raise_error %r{we couldn't find any configuration files}
    end

    it 'fails if no board id set and there are multiple boards' do
      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_board(board_id: 2, filename: 'spec/testdata/sample_board_1_configuration.json')
      project_config.load_board(board_id: 3, filename: 'spec/testdata/sample_board_1_configuration.json')

      expect { project_config.guess_board_id }.to raise_error %r{following board ids and this is ambiguous}
    end
  end

  describe '#guess_project_id' do
    it 'defaults to nil' do
      project_config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
      expect(project_config.guess_project_id).to be_nil
    end

    it 'accepts id that was passed in' do
      project_config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample', id: 2
      )
      expect(project_config.guess_project_id).to eq 2
    end

    it 'uses project id from board, if present' do
      project_config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
      project_config.all_boards[1] = sample_board.tap do |b|
        b.raw['location'] = { 'type' => 'project', 'id' => 1 }
      end
      expect(project_config.guess_project_id).to eq 1
    end

    it 'uses project id when only one unique one is specified' do
      project_config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
      project_config.all_boards[1] = sample_board.tap do |b|
        b.raw['location'] = { 'type' => 'project', 'id' => 1 }
      end
      project_config.all_boards[2] = sample_board.tap do |b|
        b.raw['location'] = { 'type' => 'user', 'id' => 2 }
      end
      expect(project_config.guess_project_id).to eq 1
    end

    it 'returns nil when project id is different on different boards (ambiguous)' do
      project_config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
      project_config.all_boards[1] = sample_board.tap do |b|
        b.raw['location'] = { 'type' => 'project', 'id' => 1 }
      end
      project_config.all_boards[2] = sample_board.tap do |b|
        b.raw['location'] = { 'type' => 'project', 'id' => 2 }
      end
      expect(project_config.guess_project_id).to be_nil
    end
  end

  describe '#discard_changes_before' do
    it 'discards for date provided' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-01')
      add_mock_change(issue: issue1, field: 'status', value: 'Backlog', value_id: 10_000, time: '2022-01-02')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-03')

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1

      issue1.board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-01-01'), nil]
      ]

      project_config.discard_changes_before status_becomes: 'Backlog'
      aggregate_failures do
        expect(issue1.changes.collect(&:time)).to eq [to_time('2022-01-03')]
        expect(project_config.discarded_changes_data).to eq [
          { cutoff_time: to_time('2022-01-02'), original_start_time: to_time('2022-01-01'), issue: issue1 }
        ]
      end
    end

    it 'does not record a discard whose cutoff predates the issue start' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'Backlog', value_id: 10_000, time: '2022-01-02')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-06')

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1
      issue1.board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-01-05'), nil]
      ]

      project_config.discard_changes_before status_becomes: 'Backlog'
      expect(project_config.discarded_changes_data).to be_nil
    end

    it 'processes every issue, skipping ones with no matching status' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-01')
      issue2 = empty_issue created: '2022-01-01', board: board, key: 'SP-2'
      issue2.changes.clear
      add_mock_change(issue: issue2, field: 'status', value: 'Backlog', value_id: 10_000, time: '2022-01-02')
      add_mock_change(issue: issue2, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-03')

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1 << issue2
      board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-01-01'), nil],
        [issue2, to_time('2022-01-01'), nil]
      ]

      project_config.discard_changes_before status_becomes: 'Backlog'
      expect(project_config.discarded_changes_data.map { |entry| entry[:issue] }).to eq [issue2]
    end

    it 'uses the named status, not the backlog statuses, for a non-backlog status name' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'Backlog', value_id: 10_000, time: '2022-01-01')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-02')

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1
      issue1.board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-01-01'), nil]
      ]

      project_config.discard_changes_before status_becomes: 'In Progress'
      expect(project_config.discarded_changes_data.first[:cutoff_time]).to eq to_time('2022-01-02')
    end

    it 'discards for block provided' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-02T07:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'Backlog', value_id: 10_000, time: '2022-01-02T08:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-02T09:00:00')

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1
      issue1.board.cycletime = default_cycletime_config

      project_config.discard_changes_before { |_issue| to_time('2022-01-02T09:00:00') }
      expect(issue1.changes.collect(&:time)).to eq []
    end

    it 'raises an error when the status name cannot be found' do
      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1

      expect { project_config.discard_changes_before status_becomes: 'No Such Status' }
        .to raise_error(/discard_changes_before.*No Such Status.*not found/i)
    end

    it 'raises an error when a status id cannot be found' do
      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1

      expect { project_config.discard_changes_before status_becomes: '99999' }
        .to raise_error(/discard_changes_before.*"99999".*not found/i)
    end

    it 'expands :backlog to the backlog statuses on the board' do
      board.raw['columnConfig']['columns'] = [
        {
          'name' => 'Backlog',
          'statuses' => [
            {
              'id' => '10000'
            }
          ]
        }
      ]
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-01')
      add_mock_change(issue: issue1, field: 'status', value: 'Backlog', value_id: 10_000, time: '2022-01-02')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2022-01-03')

      # Verify that Backlog is the only status in backlog statuses. Otherwise the test is meaningless.
      expect(issue1.board.backlog_statuses.collect { |s| "#{s.name.inspect}:#{s.id}" }).to eq ['"Backlog":10000']

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1
      issue1.board.cycletime = default_cycletime_config

      project_config.discard_changes_before status_becomes: [:backlog]
      expect(issue1.changes.collect(&:time)).to eq [
        to_time('2022-01-03')
      ]
    end
  end

  describe '#name' do
    it 'allows name' do
      project_config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
      expect(project_config.name).to eq 'sample'
    end

    it 'does not require name' do
      project_config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil
      )
      expect(project_config.name).to eq ''
    end
  end

  describe '#group_filenames_and_board_ids' do
    let(:issue_path) { File.join %w[spec tmp] }

    before do
      # Empty the directory so we can insert our own here
      Dir.foreach(issue_path) do |filename|
        full_path = File.join(issue_path, filename)
        File.unlink(full_path) unless filename.start_with?('.') || File.directory?(full_path)
      end
    end

    it 'ignores files that do not match the file convention' do
      # FAKE-123.json and FAKE-123-456.json are both valid filenames
      File.write(File.join([issue_path, 'foo']), 'content')

      expect(project_config.group_filenames_and_board_ids path: issue_path).to be_empty
    end

    it 'one file with a board id' do
      File.write(File.join([issue_path, 'FAKE-123-456.json']), 'content')
      expect(project_config.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123-456.json' => [456]
      })
    end

    it 'one file without a board id' do
      File.write(File.join([issue_path, 'FAKE-123.json']), 'content')
      expect(project_config.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123.json' => :unknown
      })
    end

    it 'multiple files, all with board ids' do
      FileUtils.touch File.join(issue_path, 'FAKE-123-456.json'), mtime: Time.now - 1000
      FileUtils.touch File.join(issue_path, 'FAKE-123-789.json'), mtime: Time.now - 2000

      expect(project_config.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123-456.json' => [456, 789]
      })
    end

    it 'multiple files, one without board id' do
      FileUtils.touch File.join(issue_path, 'FAKE-123-456.json'), mtime: Time.now - 1000
      FileUtils.touch File.join(issue_path, 'FAKE-123.json'), mtime: Time.now - 2000

      expect(project_config.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123-456.json' => [456]
      })
    end

    it 'complex example with multiple keys' do
      FileUtils.touch File.join(issue_path, 'FAKE-333-444.json'), mtime: Time.now - 1000
      FileUtils.touch File.join(issue_path, 'FAKE-123-456.json'), mtime: Time.now - 1000
      FileUtils.touch File.join(issue_path, 'FAKE-123.json'), mtime: Time.now - 2000

      expect(project_config.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123-456.json' => [456],
        'FAKE-333-444.json' => [444]
      })
    end
  end

  describe '#add_issues' do
    it 'adds both boards and issues' do
      board = sample_board
      issue = load_issue('SP-1', board: board)
      project_config.add_issues([issue])

      aggregate_failures do
        expect(project_config.all_boards.collect { |id, b| [id, b.id] }).to eql([[1, 1]])
        expect(project_config.issues).to eql([issue])
      end
    end

    it 'accumulates boards across multiple calls' do
      issue1 = load_issue('SP-1', board: board)

      raw = JSON.parse(file_read('spec/testdata/sample_board_1_configuration.json'))
      raw['id'] = 2
      board2 = Board.new(raw: raw, possible_statuses: load_statuses('./spec/testdata/sample_statuses.json'))
      board2.project_config = project_config
      issue2 = empty_issue created: '2021-01-01', board: board2, key: 'SP-999'

      project_config.add_issues([issue1])
      project_config.add_issues([issue2])

      aggregate_failures do
        expect(project_config.all_boards.keys.sort).to eq [1, 2]
        expect(project_config.issues).to include(issue1, issue2)
      end
    end
  end

  describe '#status_category_mapping' do
    let(:project_config) do
      described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      ).tap do |subject|
        exporter.file_system.when_loading file: 'spec/testdata/sample_statuses.json', json: :not_mocked
        exporter.file_system.when_loading file: 'spec/testdata/sample_board_1_configuration.json', json: :not_mocked

        subject.file_prefix 'sample'
        subject.load_status_category_mappings
        issue = empty_issue created: '2024-01-01'

        # Throw in one change that isn't a status to see if we blow up.
        issue.changes << mock_change(field: 'Flagged', time: '2024-01-02', value: 'Flagged')

        issue.changes << mock_change(
          field: 'status', time: '2024-01-02',
          value: 'Walk', value_id: 99, old_value: 'Walk', old_value_id: 100
        )
        issue.changes << mock_change(
          field: 'status', time: '2024-01-03',
          value: 'Run', value_id: 101
        )
        subject.add_issues([issue])
      end
    end

    it 'raises error if status_id cannot be guessed because no names match anything in issue histories' do
      project_config.status_category_mapping status: 'foo', category: 'To Do'
      expect(exporter.file_system.log_messages).to eq([
        "Warning: For status_category_mapping status: \"foo\", category: \"To Do\"\nCannot guess status id " \
        'for "foo" as no statuses found anywhere in the issues histories with that name. Since we can\'t find ' \
        'it, you probably don\'t need this mapping anymore so we\'re going to ignore it. If you really want it, ' \
        'then you\'ll need to specify a status id.'
      ])
    end

    it 'raises error if status_id cannot be guessed because too many names match' do
      expect { project_config.status_category_mapping status: 'Walk', category: 'To Do' }
        .to raise_error 'Cannot guess status id as there are multiple ids for the name "Walk". Perhaps it\'s ' \
          'one of [99, 100]. If you need this mapping then you must specify the status_id.'
      expect(exporter.file_system.log_messages).to be_empty
    end

    it 'raises error if category name can\'t be found' do
      expect { project_config.status_category_mapping status: 'Run:101', category: 'unknown' }
        .to raise_error 'No status categories found for name "unknown" in ["To Do":2, "Done":3, "In Progress":4]. ' \
          'Either fix the name or add an ID.'
      expect(exporter.file_system.log_messages).to be_empty
    end

    it 'raises error if category name and id do not match' do
      expect { project_config.status_category_mapping status: 'Run:101', category: 'To Do:500' }
        .to raise_error 'ID is incorrect for status category "To Do". Did you mean 2?'
      expect(exporter.file_system.log_messages).to be_empty
    end

    it 'guesses status id correctly and registers the status' do
      project_config.status_category_mapping status: 'Run', category: 'To Do'
      status = project_config.possible_statuses.find_by_id(101)
      aggregate_failures do
        expect(status.name).to eq 'Run'
        expect(status.category.name).to eq 'To Do'
        expect(exporter.file_system.log_messages).to eq([
          'status_category_mapping for "Run" has been mapped to id 101. ' \
            "If that's incorrect then specify the status_id."
        ])
      end
    end

    # This is theoretically impossible and we haven't seen it in production yet, but this is Jira.
    it 'raises error when category id missing and multiple names match' do
      project_config.possible_statuses << Status.new(
        name: 'Fake', id: 100, category_name: 'To Do', category_id: 101, category_key: 'new'
      )
      expect { project_config.status_category_mapping status: 'Run:101', category: 'To Do' }.to raise_error(
        'More than one status category found with the name "To Do" in ["To Do":2, "To Do":101]. ' \
          'Either fix the name or add an ID'
      )
      expect(exporter.file_system.log_messages).to be_empty
    end

    it 'does nothing while the exporter is downloading' do
      allow(exporter).to receive(:downloading?).and_return(true)
      project_config.status_category_mapping status: 'Run', category: 'To Do'
      aggregate_failures do
        expect(project_config.possible_statuses.find_by_id(101)).to be_nil
        expect(exporter.file_system.log_messages).to be_empty
      end
    end

    it 'registers the status with its category when an explicit category id matches' do
      project_config.status_category_mapping status: 'Run:101', category: 'To Do:2'
      status = project_config.possible_statuses.find_by_id(101)
      aggregate_failures do
        expect(status.name).to eq 'Run'
        expect(status.category.name).to eq 'To Do'
        expect(status.category.id).to eq 2
        expect(status.category.key).to eq 'new'
        expect(exporter.file_system.log_messages).to be_empty
      end
    end
  end

  describe '#add_possible_status' do
    let(:project_config) do
      described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
    end

    it 'registers a status' do
      expect(project_config.possible_statuses).to be_empty
      project_config.id = 100
      project_config.add_possible_status(
        Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, category_key: 'new'
      )
      expect(project_config.possible_statuses.collect(&:name)).to eq(['foo'])
    end

    it 'throws error if categories dont match' do
      status1 = Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, category_key: 'new'
      status2 = Status.new name: 'foo', id: 1, category_name: 'cfoo2', category_id: 3, category_key: 'new'
      project_config.add_possible_status(status1)

      expect { project_config.add_possible_status(status2) }.to raise_error(
        'Redefining status category for status "foo":1. original: "cfoo":2, new: "cfoo2":3'
      )
    end

    it 'throws error if status names dont match' do
      status1 = Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, category_key: 'new'
      status2 = Status.new name: 'bar', id: 1, category_name: 'cfoo', category_id: 2, category_key: 'new'
      project_config.add_possible_status(status1)

      expect { project_config.add_possible_status(status2) }.to raise_error(
        'Attempting to redefine the name for status 1 from "foo" to "bar"'
      )
    end

    it 'does nothing if we are just adding the same one again' do
      status1 = Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, category_key: 'new'
      status2 = Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, category_key: 'new'
      project_config.add_possible_status(status1)
      project_config.add_possible_status(status2)

      expect(project_config.possible_statuses.collect(&:name)).to eq ['foo']
    end
  end

  describe 'load_status_history' do
    it 'skips when file missing' do
      project_config.file_prefix 'sample'
      project_config.load_status_history
      aggregate_failures do
        expect(exporter.file_system.log_messages).to be_empty
        expect(project_config.possible_statuses.historical_status_mappings).to be_empty
      end
    end

    it 'continues even if load fails' do
      project_config.file_prefix 'sample'
      exporter.file_system.when_loading file: 'spec/testdata/sample_status_history.json', json: 'xxx'

      project_config.load_status_history
      aggregate_failures do
        expect(exporter.file_system.log_messages).to match_strings [
          'Loading historical statuses',
          /^Warning: Unable to load status history/
        ]
        expect(project_config.possible_statuses.historical_status_mappings).to be_empty
      end
    end

    it 'loads successfully' do
      project_config.file_prefix 'sample'
      exporter.file_system.when_loading file: 'spec/testdata/sample_status_history.json', json: [
        {
          'name' => 'Doing',
          'id' => '100',
          'statusCategory' => {
            'id' => 4,
            'key' => 'indeterminate',
            'name' => 'In Progress'
          }
        }
      ]

      project_config.load_status_history
      aggregate_failures do
        expect(exporter.file_system.log_messages).to match_strings [
          'Loading historical statuses'
        ]
        expect(project_config.possible_statuses.historical_status_mappings).to eq({
          '"Doing":100' => Status::Category.new(id: 4, name: 'In Progress', key: 'indeterminate')
        })
      end
    end
  end

  describe '#settings' do
    it 'loaded settings' do
      expect(project_config.settings['stalled_threshold_days']).not_to be_nil
    end
  end

  describe '#load_project_metadata' do
    it 'adjusts start for no_earlier_than' do
      project_config.file_prefix 'sample'
      project_config.download do
        no_earlier_than '2024-01-15'
      end
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: {
        'date_start' => '2024-01-01',
        'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-15')..to_time('2024-04-01T23:59:59')
    end

    it 'leaves start alone when no download block at all' do
      project_config.file_prefix 'sample'
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: {
        'date_start' => '2024-01-01',
        'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-01')..to_time('2024-04-01T23:59:59')
    end

    it 'leaves start alone when no_earlier_than not specified' do
      project_config.file_prefix 'sample'
      project_config.download(&empty_config_block)
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: {
        'date_start' => '2024-01-01',
        'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-01')..to_time('2024-04-01T23:59:59')
    end

    it 'leaves start alone when no_earlier_than is already earlier than start' do
      project_config.file_prefix 'sample'
      project_config.download do
        no_earlier_than '2023-12-15'
      end
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: {
        'date_start' => '2024-01-01',
        'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-01')..to_time('2024-04-01T23:59:59')
    end

    it 'reads the data version and jira url from the metadata' do
      project_config.file_prefix 'sample'
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: {
        'version' => 3, 'jira_url' => 'https://example.atlassian.net',
        'date_start' => '2024-01-01', 'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      aggregate_failures do
        expect(project_config.data_version).to eq 3
        expect(project_config.jira_url).to eq 'https://example.atlassian.net'
      end
    end

    it 'defaults the data version to 1 when the metadata omits it' do
      project_config.file_prefix 'sample'
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: {
        'date_start' => '2024-01-01', 'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.data_version).to eq 1
    end

    it 'falls back to the old time_start/time_end fields when the date_ fields are absent' do
      project_config.file_prefix 'sample'
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: {
        'time_start' => '2024-01-01', 'time_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-01')..to_time('2024-04-01T23:59:59')
    end

    it 'logs and re-raises when the metadata file is missing' do
      # 'missing_meta.json' is never mocked, so the load raises Errno::ENOENT.
      project_config.file_prefix 'missing'
      expect { project_config.load_project_metadata }.to raise_error(Errno::ENOENT)
      expect(exporter.file_system.log_messages).to include(a_string_matching(/Can't load .*missing_meta\.json/))
    end
  end

  describe '#issues' do
    it 'warns when issues directory missing' do
      # We have to create our own project_config here as the default one at the top of the file will have
      # already loaded issues so it's too late.
      project_config = described_class.new(exporter: exporter, target_path: target_path, jira_config: nil, block: nil)
      exporter.file_system.when_loading file: 'spec/testdata/sample_meta.json', json: nil
      exporter.file_system.when_loading file: 'spec/testdata/sample_statuses.json', json: :not_mocked
      exporter.file_system.when_loading file: 'spec/testdata/sample_board_1_configuration.json', json: :not_mocked

      project_config.file_prefix 'sample'
      expect { project_config.issues }.to raise_error(
        'No data found. Must do a download before an export'
      )
    end

    it 'raises error when issues used before boards configured' do
      # We have to create our own project_config here as the default one at the top of the file will have
      # already loaded issues so it's too late.
      path = 'spec/complete_sample/'
      project_config = described_class.new(exporter: exporter, target_path: path, jira_config: nil, block: nil)
      exporter.file_system.when_loading file: "#{path}sample_meta.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{path}sample_statuses.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{path}sample_board_1_configuration.json", json: :not_mocked
      exporter.file_system.when_loading file: "#{path}sample_issues/SP-7.json", json: :not_mocked
      exporter.file_system.when_foreach root: "#{path}sample_issues", result: :not_mocked

      project_config.file_prefix 'sample'
      expect { project_config.issues }.to raise_error(
        "The board declaration for board 1 must come before the first usage of 'issues' in the configuration"
      )
    end

    context 'when loading issues from a directory on disk' do
      let(:loaded_config) do
        described_class.new(
          exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil, name: 'sample'
        ).tap do |config|
          exporter.file_system.when_loading(
            file: 'spec/complete_sample/sample_board_1_configuration.json', json: :not_mocked
          )
          exporter.file_system.when_loading file: 'spec/complete_sample/sample_statuses.json', json: :not_mocked
          exporter.file_system.when_loading file: 'spec/complete_sample/sample_meta.json', json: :not_mocked
          exporter.file_system.when_foreach root: 'spec/complete_sample/sample_issues', result: :not_mocked
          [1, 2, 5, 7, 8, 11].each do |num|
            exporter.file_system.when_loading(
              file: "spec/complete_sample/sample_issues/SP-#{num}.json", json: :not_mocked
            )
          end

          config.file_prefix 'sample'
          config.load_status_category_mappings
          config.load_all_boards
          config.board id: 1 do
            cycletime do
              start_at first_time_in_status_category(:indeterminate)
              stop_at first_time_in_status_category(:done)
            end
          end
          config.time_range = to_time('2021-06-01')..to_time('2021-09-01')
        end
      end

      it 'loads every issue from the directory' do
        expect(loaded_config.issues.collect(&:key)).to contain_exactly(
          'SP-1', 'SP-2', 'SP-5', 'SP-7', 'SP-8', 'SP-11'
        )
      end

      it 'memoizes the loaded issues so a second call returns the same collection' do
        first_load = loaded_config.issues
        expect(loaded_config.issues).to be(first_load)
      end

      it 'attaches github pull requests after loading' do
        allow(loaded_config).to receive(:attach_github_prs)
        loaded_config.issues
        expect(loaded_config).to have_received(:attach_github_prs)
      end

      it 'logs its progress through the load and attach phases' do
        loaded_config.issues
        expect(exporter.file_system.log_messages).to include(
          a_string_matching(%r{\[diag\] Loading issues from .*sample_issues}),
          '[diag] Loaded 6 issues from disk',
          '[diag] Starting attach phase',
          '[diag] Attach phase complete',
          '[diag] Retained 6 primary issues'
        )
      end

      it 'drops issues that were not part of the initial query' do
        config = loaded_config # trigger the setup, which mocks SP-1 as :not_mocked
        raw = JSON.parse(file_read('spec/complete_sample/sample_issues/SP-1.json'))
        raw['exporter'] = { 'in_initial_query' => false }
        exporter.file_system.when_loading file: 'spec/complete_sample/sample_issues/SP-1.json', json: raw

        expect(config.issues.collect(&:key)).to contain_exactly('SP-2', 'SP-5', 'SP-7', 'SP-8', 'SP-11')
      end

      it 'attaches related issues, resolving references by key against the loaded set' do
        config = loaded_config # trigger the setup, which mocks SP-2 as :not_mocked
        raw = JSON.parse(file_read('spec/complete_sample/sample_issues/SP-2.json'))
        raw['fields']['subtasks'] = [{ 'key' => 'SP-1' }]
        raw['fields']['parent'] = { 'key' => 'SP-5' }
        raw['fields']['issuelinks'] = [{
          'id' => '10001',
          'type' => { 'name' => 'Blocks', 'inward' => 'is blocked by', 'outward' => 'blocks' },
          'inwardIssue' => {
            'key' => 'SP-7',
            'fields' => {
              'summary' => 'Linked issue',
              'status' => {
                'name' => 'Done', 'id' => '10002',
                'statusCategory' => { 'id' => 3, 'key' => 'done', 'name' => 'Done' }
              },
              'priority' => { 'name' => 'Medium', 'id' => '3' },
              'issuetype' => { 'name' => 'Story', 'id' => '10001', 'subtask' => false }
            }
          }
        }]
        exporter.file_system.when_loading file: 'spec/complete_sample/sample_issues/SP-2.json', json: raw

        sp2 = config.issues.find { |issue| issue.key == 'SP-2' }
        aggregate_failures do
          expect(sp2.subtasks.collect(&:key)).to eq ['SP-1']
          expect(sp2.parent.key).to eq 'SP-5'
          # The linked issue's placeholder is swapped for the real loaded SP-7 object.
          expect(sp2.issue_links.first.other_issue).to be(config.issues.find { |issue| issue.key == 'SP-7' })
        end
      end
    end

    it 'returns an empty memoized collection while downloading' do
      config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'downloading'
      )
      allow(exporter).to receive(:downloading?).and_return(true)
      first_call = config.issues
      aggregate_failures do
        expect(first_call.collect(&:key)).to eq []
        expect(config.issues).to be(first_call)
      end
    end

    it 'raises when an aggregated project reaches issues without any wired in' do
      config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'agg'
      )
      allow(config).to receive(:aggregated_project?).and_return(true)
      expect { config.issues }.to raise_error(/This is an aggregated project/)
    end

    it 'loads data and warns when the issues directory is absent' do
      config = described_class.new(
        exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil, name: 'missing'
      )
      allow(config).to receive(:data_downloaded?).and_return(true)
      allow(config).to receive(:load_data)
      config.file_prefix 'nonexistent'
      # all_boards is empty so load_data must run; spec/testdata/nonexistent_issues is not a real directory.
      result = config.issues
      aggregate_failures do
        expect(config).to have_received(:load_data)
        expect(result.collect(&:key)).to eq []
        expect(exporter.file_system.log_messages)
          .to include(a_string_matching(/Can't find directory .*nonexistent_issues/))
      end
    end
  end

  describe '#find_default_board' do
    it 'defaults to first when multiple' do
      board4 = sample_board
      board4.raw['id'] = '4'
      board5 = sample_board
      board5.raw['id'] = '5'
      project_config.all_boards[board4.id] = board4
      project_config.all_boards[board5.id] = board5

      expect(project_config.find_default_board.id).to be 4
      expect(exporter.file_system.log_messages).to eq([
        'Multiple boards are in use for project "one". Picked "SP board" to attach issues to.'
      ])
    end

    it 'raises error when no boards' do
      expect { project_config.find_default_board }.to raise_error 'No boards found for project "one"'
    end
  end

  describe '#load_sprints' do
    it "ignores sprint data that doesn't correspond to a known board" do
      exporter.file_system.when_foreach root: 'spec/testdata/', result: ['foo.json', 'sample_board_2_sprints_0.json']

      project_config.file_prefix 'sample'
      project_config.all_boards[1] = sample_board
      project_config.load_sprints
      expect(exporter.file_system.log_messages).to eq([
        "Found sprint data but can't find a matching board in config. " \
          'File: spec/testdata/sample_board_2_sprints_0.json, Boards: [1]'
      ])
    end
  end

  describe '#load_fix_versions' do
    it 'loads fix versions from file' do
      project_config.file_prefix 'sample'
      raw = [{ 'id' => '10', 'name' => 'v1.0', 'released' => true, 'releaseDate' => '2026-01-15' }]
      exporter.file_system.when_loading file: 'spec/testdata/sample_fix_versions.json', json: raw

      project_config.load_fix_versions

      expect(project_config.fix_versions.size).to eq(1)
      expect(project_config.fix_versions.first).to be_a(FixVersion)
      expect(project_config.fix_versions.first.name).to eq('v1.0')
    end

    it 'leaves fix_versions empty when file does not exist' do
      project_config.file_prefix 'sample'

      project_config.load_fix_versions

      expect(project_config.fix_versions).to be_empty
    end
  end

  describe '#file_prefix' do
    it 'can only be set once' do
      project_config.file_prefix 'sample'
      expect { project_config.file_prefix 'second' }.to raise_error(
        'file_prefix can only be set once. Was "sample" and now changed to "second".'
      )
    end

    it 'raises error if file_prefix not set early enough' do
      expect { project_config.get_file_prefix }.to raise_error(
        'file_prefix has not been set yet. Move it to the top of the project declaration.'
      )
    end

    it 'raises error if the file_prefix is reused' do
      project_config.file_prefix 'sample'
      exporter.project_configs << project_config

      project_config2 = described_class.new(
        exporter: exporter, target_path: target_path, name: 'Two', jira_config: nil, block: nil
      )
      exporter.project_configs << project_config2

      expect { project_config2.file_prefix 'sample' }.to raise_error(
        'Project "Two" specifies file prefix "sample", but that is already used by project "one" ' \
        'in the same target path "spec/testdata/". This is almost guaranteed to be too much copy ' \
        'and paste in your configuration. File prefixes must be unique within a directory.'
      )
    end
  end

  describe '#run' do
    it 'does not anonymize data when load_only is true' do
      project_config.anonymize
      allow(project_config).to receive(:load_data)
      allow(project_config).to receive(:anonymize_data)
      project_config.run(load_only: true)
      expect(project_config).not_to have_received(:anonymize_data)
    end
  end

  describe '#resolve_blocked_stalled_status_settings' do
    before do
      project_config.file_prefix 'sample'
    end

    it 'resolves status names to a StatusCollection' do
      project_config.settings['blocked_statuses'] = ['Review']
      project_config.settings['stalled_statuses'] = ['In Progress']
      project_config.send(:resolve_blocked_stalled_status_settings)

      expect(project_config.settings['blocked_statuses']).to be_a StatusCollection
      expect(project_config.settings['blocked_statuses'].collect(&:name)).to eq ['Review']
      expect(project_config.settings['stalled_statuses'].collect(&:name)).to eq ['In Progress']
      expect(exporter.file_system.log_messages).to be_empty
    end

    it 'supports id-only lookup' do
      project_config.settings['blocked_statuses'] = ['10011']
      project_config.settings['stalled_statuses'] = []
      project_config.send(:resolve_blocked_stalled_status_settings)

      expect(project_config.settings['blocked_statuses'].collect(&:name)).to eq ['Review']
    end

    it 'supports name:id pair lookup' do
      project_config.settings['blocked_statuses'] = ['Review:10011']
      project_config.settings['stalled_statuses'] = []
      project_config.send(:resolve_blocked_stalled_status_settings)

      expect(project_config.settings['blocked_statuses'].collect(&:name)).to eq ['Review']
    end

    it 'warns and skips statuses that cannot be found' do
      project_config.settings['blocked_statuses'] = ['NonExistent']
      project_config.settings['stalled_statuses'] = []
      project_config.send(:resolve_blocked_stalled_status_settings)

      aggregate_failures do
        expect(project_config.settings['blocked_statuses']).to be_empty
        expect(exporter.file_system.log_messages).to eq [
          'Warning: Status "NonExistent" in blocked_statuses not found. Ignoring.'
        ]
      end
    end

    it 'processes remaining statuses after a not-found one' do
      project_config.settings['blocked_statuses'] = %w[NonExistent Review]
      project_config.settings['stalled_statuses'] = []
      project_config.send(:resolve_blocked_stalled_status_settings)

      expect(project_config.settings['blocked_statuses'].collect(&:name)).to eq ['Review']
    end
  end

  describe '#stringify_keys' do
    it 'converts symbol keys to strings at the top level' do
      expect(project_config.send(:stringify_keys, { foo: 1, bar: 2 })).to eq({ 'foo' => 1, 'bar' => 2 })
    end

    it 'converts symbol keys inside nested hashes' do
      input = { outer: { inner: 'value' } }
      expect(project_config.send(:stringify_keys, input)).to eq({ 'outer' => { 'inner' => 'value' } })
    end

    it 'converts symbol keys inside hashes nested in arrays' do
      input = { annotations: [{ date: '2026-01-01', label: 'Jan' }] }
      expect(project_config.send(:stringify_keys, input)).to eq(
        { 'annotations' => [{ 'date' => '2026-01-01', 'label' => 'Jan' }] }
      )
    end

    it 'leaves non-hash, non-array values untouched' do
      expect(project_config.send(:stringify_keys, 'hello')).to eq('hello')
      expect(project_config.send(:stringify_keys, 42)).to eq(42)
    end
  end

  describe '#load_settings' do
    it 'returns a hash with only string keys' do
      expect(project_config.settings.keys).to all(be_a(String))
    end
  end
end
