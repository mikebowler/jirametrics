# frozen_string_literal: true

require './spec/spec_helper'

describe ProjectConfig do
  let(:exporter) { Exporter.new }
  let(:target_path) { 'spec/testdata/' }
  let(:subject) { ProjectConfig.new exporter: exporter, target_path: target_path, jira_config: nil, block: nil }

  context 'category_for' do
    it "where mapping doesn't exist" do
      subject.file_prefix 'sample'
      subject.status_category_mapping status: 'Doing', category: 'In progress'
      subject.status_category_mapping status: 'Done', category: 'Done'
      subject.load_all_boards
      expect { subject.category_for status_name: 'Foo' }
        .to raise_error(/^Could not determine categories for some/)
    end

    it 'where mapping does exist' do
      subject.file_prefix 'sample'
      subject.status_category_mapping status: 'Doing', category: 'InProgress'
      expect(subject.category_for(status_name: 'Doing')).to eql 'InProgress'
    end
  end

  context 'board_configuration' do
    it 'should load' do
      subject.file_prefix 'sample'
      subject.load_all_boards
      expect(subject.all_boards.keys).to eq [1]

      contents = subject.all_boards[1].visible_columns.collect do |column|
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
    it 'should degrade gracefully when mappings not found' do
      subject.load_status_category_mappings
      expect(subject.possible_statuses).to be_empty
    end

    it 'should load' do
      subject.file_prefix 'sample'
      subject.load_status_category_mappings

      expected = [
        ['Backlog', 'To Do'],
        ['Done', 'Done'], # rubocop:disable Style/WordArray
        ['In Progress', 'In Progress'],
        ['Review', 'In Progress'],
        ['Selected for Development', 'In Progress']
      ]

      actual = subject.possible_statuses.collect do |status|
        [status.name, status.category_name]
      end

      expect(actual.sort).to eq expected.sort
    end
  end

  context 'download/aggregate config' do
    let(:empty_block) { ->(_) {} }

    it 'should fail if a second download is set' do
      subject.download do
        file_suffix 'a'
      end
      expect { subject.download { file_suffix 'a' } }.to raise_error(
        'Not allowed to have multiple download blocks in one project'
      )
    end
  end

  context 'evaluate_next_level' do
    it 'should execute the original block that had been passed in, in its own context' do
      columns = ProjectConfig.new exporter: nil, target_path: nil, jira_config: nil, block: ->(_) { self.class.to_s }
      expect(columns.evaluate_next_level).to eq('ProjectConfig')
    end
  end

  context 'guess_board_id' do
    it 'should fail if no board id set and there are no boards' do
      expect { subject.guess_board_id }.to raise_error %r{we couldn't find any configuration files}
    end

    it 'should fail if no board id set and there are multiple boards' do
      subject.load_board(board_id: 2, filename: 'spec/testdata/sample_board_1_configuration.json')
      subject.load_board(board_id: 3, filename: 'spec/testdata/sample_board_1_configuration.json')

      expect { subject.guess_board_id }.to raise_error %r{following board ids and this is ambiguous}
    end
  end

  context 'discard_changes_before' do
    let(:issue1) { load_issue('SP-1') }

    it 'should discard for date provided' do
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-01')
      issue1.changes << mock_change(field: 'status', value: 'backlog', time: '2022-01-02')
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-03')

      subject.file_prefix 'sample'
      subject.load_all_boards
      subject.issues << issue1

      subject.discard_changes_before status_becomes: 'backlog'
      expect(issue1.changes.collect(&:time)).to eq [
        Time.parse('2022-01-03')
      ]
    end

    it 'should discard for block provided' do
      issue1.changes.clear
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-02T07:00:00')
      issue1.changes << mock_change(field: 'status', value: 'backlog', time: '2022-01-02T08:00:00')
      issue1.changes << mock_change(field: 'status', value: 'doing', time: '2022-01-02T09:00:00')

      subject.file_prefix 'sample'
      subject.load_all_boards
      subject.issues << issue1

      subject.discard_changes_before { |_issue| Time.parse('2022-01-02T09:00:00') }
      expect(issue1.changes.collect(&:time)).to eq []
    end
  end

  context 'name' do
    it 'should allow name' do
      project_config = ProjectConfig.new(
        exporter: exporter, target_path: target_path, jira_config: nil, block: nil, name: 'sample'
      )
      expect(project_config.name).to eq 'sample'
    end

    it 'should not require name' do
      expect(subject.name).to eq ''
    end
  end

  context 'group_filenames_and_board_ids' do
    let(:issue_path) { File.join %w[spec tmp] }
    before(:each) do
      # Empty the directory so we can insert our own here
      Dir.foreach(issue_path) do |filename|
        full_path = File.join(issue_path, filename)
        File.unlink(full_path) unless filename.start_with?('.') || File.directory?(full_path)
      end
    end

    it 'should ignore files that do not match the file convention' do
      # FAKE-123.json and FAKE-123-456.json are both valid filenames
      File.write(File.join([issue_path, 'foo']), 'content')

      expect(subject.group_filenames_and_board_ids path: issue_path).to be_empty
    end

    it 'one file with a board id' do
      File.write(File.join([issue_path, 'FAKE-123-456.json']), 'content')
      expect(subject.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123-456.json' => [456]
      })
    end

    it 'one file without a board id' do
      File.write(File.join([issue_path, 'FAKE-123.json']), 'content')
      expect(subject.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123.json' => :unknown
      })
    end

    it 'multiple files, all with board ids' do
      FileUtils.touch File.join(issue_path, 'FAKE-123-456.json'), mtime: Time.now - 1000
      FileUtils.touch File.join(issue_path, 'FAKE-123-789.json'), mtime: Time.now - 2000

      expect(subject.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123-456.json' => [456, 789]
      })
    end

    it 'multiple files, one without board id' do
      FileUtils.touch File.join(issue_path, 'FAKE-123-456.json'), mtime: Time.now - 1000
      FileUtils.touch File.join(issue_path, 'FAKE-123.json'), mtime: Time.now - 2000

      expect(subject.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123-456.json' => [456]
      })
    end

    it 'complex example with multiple keys' do
      FileUtils.touch File.join(issue_path, 'FAKE-333-444.json'), mtime: Time.now - 1000
      FileUtils.touch File.join(issue_path, 'FAKE-123-456.json'), mtime: Time.now - 1000
      FileUtils.touch File.join(issue_path, 'FAKE-123.json'), mtime: Time.now - 2000

      expect(subject.group_filenames_and_board_ids path: issue_path).to eq({
        'FAKE-123-456.json' => [456],
        'FAKE-333-444.json' => [444]
      })
    end
  end
end
