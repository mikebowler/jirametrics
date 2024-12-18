# frozen_string_literal: true

require './spec/spec_helper'

describe ProjectConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:target_path) { 'spec/testdata/' }
  let(:project_config) do
    exporter.file_system.when_loading file: 'spec/testdata//sample_statuses.json', json: :not_mocked
    exporter.file_system.when_loading file: 'spec/testdata/sample_board_1_configuration.json', json: :not_mocked

    described_class.new exporter: exporter, target_path: target_path, jira_config: nil, block: nil
  end
  let(:issue1) { load_issue('SP-1') }

  context 'board_configuration' do
    it 'loads' do
      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      expect(project_config.all_boards.keys).to eq [1]

      contents = project_config.all_boards[1].visible_columns.collect do |column|
        [column.name, column.status_ids, column.min, column.max]
      end

      # rubocop:disable Layout/ExtraSpacing
      expect(contents).to eq [
        ['Ready',       [10_001],   1,   4],
        ['In Progress',      [3], nil,   3],
        ['Review',      [10_011], nil,   3],
        ['Done',        [10_002], nil, nil]
      ]
      # rubocop:enable Layout/ExtraSpacing
    end
  end

  context 'possible_statuses' do
    it 'degrades gracefully when mappings not found' do
      project_config.load_status_category_mappings
      expect(project_config.possible_statuses).to be_empty
    end

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
        [status.name, status.category_name]
      end

      expect(actual.sort).to eq expected.sort
    end
  end

  context 'download/aggregate config' do
    it 'fails if a second download is set' do
      project_config.download do
        file_suffix 'a'
      end
      expect { project_config.download { file_suffix 'a' } }.to raise_error(
        'Not allowed to have multiple download blocks in one project'
      )
    end
  end

  context 'evaluate_next_level' do
    it 'executes the original block that had been passed in, in its own context' do
      columns = described_class.new exporter: exporter, target_path: nil, jira_config: nil,
        block: ->(_) { self.class.to_s }
      expect(columns.evaluate_next_level).to eq('ProjectConfig')
    end
  end

  context 'guess_board_id' do
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

  context 'guess_project_id' do
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

  context 'discard_changes_before' do
    it 'discards for date provided' do
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-01')
      issue1.changes << mock_change(field: 'status', value: 'backlog', time: '2022-01-02')
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-03')

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1

      project_config.discard_changes_before status_becomes: 'backlog'
      expect(issue1.changes.collect(&:time)).to eq [
        to_time('2022-01-03')
      ]
    end

    it 'discards for block provided' do
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-02T07:00:00')
      issue1.changes << mock_change(field: 'status', value: 'backlog', time: '2022-01-02T08:00:00')
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-02T09:00:00')

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1

      project_config.discard_changes_before { |_issue| to_time('2022-01-02T09:00:00') }
      expect(issue1.changes.collect(&:time)).to eq []
    end

    it 'expands :backlog to the backlog statuses on the board' do
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-01')
      issue1.changes << mock_change(field: 'status', value: 'Backlog', time: '2022-01-02')
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-03')

      # Verify that Backlog is the only status in backlog statuses. Otherwise the test is meaningless.
      expect(issue1.board.backlog_statuses.collect(&:name)).to eq ['Backlog']

      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.issues << issue1

      project_config.discard_changes_before status_becomes: [:backlog]
      expect(issue1.changes.collect(&:time)).to eq [
        to_time('2022-01-03')
      ]
    end
  end

  context 'name' do
    it 'allows name' do
      project_config = described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
      expect(project_config.name).to eq 'sample'
    end

    it 'does not require name' do
      expect(project_config.name).to eq ''
    end
  end

  context 'group_filenames_and_board_ids' do
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

  context 'add_issues' do
    it 'adds both boards and issues' do
      board = sample_board
      issue = load_issue('SP-1', board: board)
      project_config.add_issues([issue])

      expect(project_config.all_boards.collect { |id, b| [id, b.id] }).to eql([[1, 1]])
      expect(project_config.issues).to eql([issue])
    end
  end

  context 'add_possible_status' do
    let(:project_config) do
      described_class.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
    end

    it 'registers a status' do
      expect(project_config.possible_statuses).to be_empty
      project_config.id = 100
      project_config.add_possible_status(
        Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2
      )
      expect(project_config.possible_statuses.collect(&:name)).to eq(['foo'])
    end

    it 'ignores a project status for a different project' do
      project_config.id = 100
      project_config.add_possible_status(
        Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, project_id: 101
      )
      expect(project_config.possible_statuses.collect(&:name)).to be_empty
    end

    it 'replaces a global status with the project specific one' do
      project_config.id = 100
      project_config.add_possible_status(
        Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, project_id: nil
      )
      expect(project_config.possible_statuses.collect(&:project_id)).to eq [nil]

      project_config.add_possible_status(
        Status.new(name: 'foo', id: 1, category_name: 'xfoo', category_id: 2, project_id: 100)
      )
      expect(project_config.possible_statuses.collect(&:project_id)).to eq [100]
    end

    it 'does not replace a global status with the project specific one because categories are the same' do
      project_config.add_possible_status(
        Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, project_id: nil
      )
      expect(project_config.possible_statuses.collect(&:project_id)).to eq [nil]

      project_config.add_possible_status(
        Status.new(name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, project_id: 100)
      )
      expect(project_config.possible_statuses.collect(&:project_id)).to eq [nil]
    end

    it 'raises ambiguous exception because we need to know the project id and cant determine it' do
      project_config.add_possible_status(
        Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2, project_id: nil
      )
      expect(project_config.possible_statuses.collect(&:project_id)).to eq [nil]

      expect do
        project_config.add_possible_status(
          Status.new(name: 'foo', id: 1, category_name: 'xfoo', category_id: 2, project_id: 100)
        )
      end.to raise_error(/^Ambiguous project id/)
    end

    it 'throws error if categories dont match' do
      status1 = Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2
      status2 = Status.new name: 'foo', id: 1, category_name: 'cfoo2', category_id: 3
      project_config.add_possible_status(status1)

      expect { project_config.add_possible_status(status2) }.to raise_error(
        /^Redefining status category/
      )
    end

    it 'does nothing if we are just adding the same one again' do
      status1 = Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2
      status2 = Status.new name: 'foo', id: 1, category_name: 'cfoo', category_id: 2
      project_config.add_possible_status(status1)
      project_config.add_possible_status(status2)

      expect(project_config.possible_statuses.collect(&:name)).to eq ['foo']
    end
  end

  context 'find_statuses_with_no_category_information' do
    it 'returns [] when no issues' do
      expect(project_config.find_statuses_with_no_category_information([])).to be_empty
    end

    it 'returns all when no statuses are found' do
      issues = [issue1]
      expect(project_config.find_statuses_with_no_category_information(issues)).to eq(
        ['Backlog', 'Selected for Development', 'In Progress']
      )
    end

    it 'returns only those missing categories' do
      issues = [issue1]
      project_config.possible_statuses << Status.new(name: 'Backlog')
      expect(project_config.find_statuses_with_no_category_information(issues)).to eq(
        ['Selected for Development', 'In Progress']
      )
    end
  end

  context 'raise_with_message_about_missing_category_information' do
    it 'raises correct error' do
      issues = [issue1]
      project_config.possible_statuses << Status.new(name: 'Backlog', category_name: 'Foo')

      expect { project_config.raise_with_message_about_missing_category_information(issues) }
        .to raise_error(
          <<~ERROR
            Could not determine categories for some of the statuses used in this data set.
            Use the 'status_category_mapping' declaration in your config to manually add one.
            The mappings we do know about are below:
              status: "Backlog", category: "Foo"

            The ones we're missing are the following:
              status: "Selected for Development", category: <unknown>
              status: "In Progress", category: <unknown>
          ERROR
          .chomp
        )
    end
  end

  it 'loaded settings' do
    expect(project_config.settings['stalled_threshold_days']).not_to be_nil
  end

  context 'load_project_metadata' do
    it 'logs error when unable to find files' do
      project_config.file_prefix 'foo'
      expect { project_config.load_project_metadata }.to raise_error(
        'No such file or directory - spec/testdata/foo_meta.json'
      )
      expect(exporter.file_system.log_messages).to eq([
        "Can't load spec/testdata/foo_meta.json. Have you done a download?"
      ])
    end

    it 'adjusts start for no_earlier_than' do
      project_config.file_prefix 'foo'
      project_config.download do
        no_earlier_than '2024-01-15'
      end
      exporter.file_system.when_loading file: 'spec/testdata/foo_meta.json', json: {
        'date_start' => '2024-01-01',
        'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-15')..to_time('2024-04-01T23:59:59')
    end

    it 'leaves start alone when no download block at all' do
      project_config.file_prefix 'foo'
      exporter.file_system.when_loading file: 'spec/testdata/foo_meta.json', json: {
        'date_start' => '2024-01-01',
        'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-01')..to_time('2024-04-01T23:59:59')
    end

    it 'leaves start alone when no_earlier_than not specified' do
      project_config.file_prefix 'foo'
      project_config.download(&empty_config_block)
      exporter.file_system.when_loading file: 'spec/testdata/foo_meta.json', json: {
        'date_start' => '2024-01-01',
        'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-01')..to_time('2024-04-01T23:59:59')
    end

    it 'leaves start alone when no_earlier_than is already earlier than start' do
      project_config.file_prefix 'foo'
      project_config.download do
        no_earlier_than '2023-12-15'
      end
      exporter.file_system.when_loading file: 'spec/testdata/foo_meta.json', json: {
        'date_start' => '2024-01-01',
        'date_end' => '2024-04-01'
      }
      project_config.load_project_metadata
      expect(project_config.time_range).to eq to_time('2024-01-01')..to_time('2024-04-01T23:59:59')
    end
  end

  context 'issues' do
    it 'warns when issues directory missing' do
      project_config.file_prefix 'foo'
      project_config.all_boards[1] = sample_board
      expect { project_config.issues }.to raise_error(
        'No data found. Must do a download before an export'
      )
    end
  end

  context 'find_default_board' do
    it 'defaults to first when multiple' do
      board4 = sample_board
      board4.raw['id'] = '4'
      board5 = sample_board
      board5.raw['id'] = '5'
      project_config.all_boards[board4.id] = board4
      project_config.all_boards[board5.id] = board5

      expect(project_config.find_default_board.id).to be 4
      expect(exporter.file_system.log_messages).to eq([
        'Multiple boards are in use for project "". Picked "SP board" to attach issues to.'
      ])
    end

    it 'raises error when no boards' do
      expect { project_config.find_default_board }.to raise_error 'No boards found for project ""'
    end
  end

  context 'load_sprints' do
    it 'loads the sprints' do
      exporter.file_system.when_foreach root: 'spec/testdata/', result: ['sample_board_1_sprints_0.json']
      exporter.file_system.when_loading(
        file: 'spec/testdata/sample_board_1_sprints_0.json',
        json: {
          'maxResults' => 50,
          'startAt' => 0,
          'total' => 1,
          'isLast' => true,
          'values' => [
            {
              'id' => 1,
              'state' => 'closed',
              'name' => 'Scrum Sprint 1',
              'startDate' => '2022-03-26T16:04:09.679Z',
              'endDate' => '2022-04-09T16:04:00.000Z',
              'completeDate' => '2022-04-10T22:17:29.972Z',
              'createdDate' => '2022-03-26T16:03:49.814Z',
              'originBoardId' => 2
            }
          ]
        }
      )

      project_config.file_prefix 'sample'
      project_config.all_boards[1] = sample_board
      project_config.load_sprints
      expect(project_config.all_boards.keys).to eq [1]
    end

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
end
