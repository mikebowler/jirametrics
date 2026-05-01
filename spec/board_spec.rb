# frozen_string_literal: true

require './spec/spec_helper'

describe Board do
  context 'url' do
    it 'fabricates url' do
      board = described_class.new raw: {
        'id' => 3,
        'self' => 'https://improvingflow.atlassian.net/rest/agile/1.0/board/3/configuration',
        'columnConfig' => {
          'columns' => []
        }
      }, possible_statuses: StatusCollection.new
      expect(board.url).to eq('https://improvingflow.atlassian.net/secure/RapidBoard.jspa?rapidView=3')
    end

    it 'throws exception if URL cannot be fabricated' do
      board = described_class.new raw: {
        'id' => 3,
        'self' => 'random string',
        'columnConfig' => {
          'columns' => []
        }
      }, possible_statuses: StatusCollection.new
      expect { board.url }.to raise_error 'Cannot parse self: "random string"'
    end
  end

  context 'project_id' do
    it 'returns nil when no location key is present' do
      board = described_class.new raw: {
        'id' => 3,
        'columnConfig' => { 'columns' => [] }
      }, possible_statuses: StatusCollection.new
      expect(board.project_id).to be_nil
    end

    it 'ignores locations that are not project' do
      board = described_class.new raw: {
        'id' => 3,
        'location' => {
          'type' => 'user',
          'id' => 2
        },
        'columnConfig' => {
          'columns' => []
        }
      }, possible_statuses: StatusCollection.new
      expect(board.project_id).to be_nil
    end

    it 'returns project_id' do
      board = described_class.new raw: {
        'id' => 3,
        'location' => {
          'type' => 'project',
          'id' => 2
        },
        'columnConfig' => {
          'columns' => []
        }
      }, possible_statuses: StatusCollection.new
      expect(board.project_id).to eq 2
    end
  end

  context 'status_ids_from_column' do
    it 'returns empty array when statuses key is absent' do
      board = load_complete_sample_board
      expect(board.status_ids_from_column({})).to eq []
    end

    it 'returns integer ids when statuses are present' do
      board = load_complete_sample_board
      column = { 'statuses' => [{ 'id' => '5' }, { 'id' => '10' }] }
      expect(board.status_ids_from_column(column)).to eq [5, 10]
    end
  end

  context 'status_ids_in_or_right_of_column' do
    it 'returns ids from the named column and all columns to its right' do
      board = load_complete_sample_board
      expect(board.status_ids_in_or_right_of_column('In Progress')).to eq [3, 10_011, 10_002]
    end

    it 'returns all visible column ids when given the leftmost column' do
      board = load_complete_sample_board
      expect(board.status_ids_in_or_right_of_column('Ready')).to eq [10_001, 3, 10_011, 10_002]
    end

    it 'returns only that column\'s ids when given the rightmost column' do
      board = load_complete_sample_board
      expect(board.status_ids_in_or_right_of_column('Done')).to eq [10_002]
    end

    it 'raises when column name is not found' do
      board = load_complete_sample_board
      expect { board.status_ids_in_or_right_of_column('Nonexistent') }.to raise_error(
        /No visible column with name: "Nonexistent"/
      )
    end

    it 'includes the column names in the error message' do
      board = load_complete_sample_board
      expect { board.status_ids_in_or_right_of_column('Nonexistent') }.to raise_error(
        /"Ready".*"In Progress".*"Review".*"Done"/
      )
    end
  end

  context 'backlog_statuses' do
    it 'returns statuses from the first column for a kanban board' do
      board = load_complete_sample_board
      expect(board.backlog_statuses.map(&:id)).to eq [10_000]
    end

    it 'returns empty for a non-kanban board' do
      board = described_class.new raw: {
        'id' => 1,
        'type' => 'scrum',
        'columnConfig' => { 'columns' => [] }
      }, possible_statuses: StatusCollection.new
      expect(board.backlog_statuses).to be_empty
    end
  end

  context 'scrum? and kanban? for natively typed boards' do
    it 'is scrum for a board with type scrum' do
      board = described_class.new raw: {
        'id' => 1,
        'type' => 'scrum',
        'columnConfig' => { 'columns' => [] }
      }, possible_statuses: StatusCollection.new
      expect(board.scrum?).to be true
      expect(board.kanban?).to be false
    end

    it 'is kanban for a board with type kanban' do
      board = load_complete_sample_board
      expect(board.scrum?).to be false
      expect(board.kanban?).to be true
    end
  end

  context 'team_managed_kanban?' do
    let(:simple_raw) { { 'id' => 1, 'type' => 'simple', 'columnConfig' => { 'columns' => [] } } }
    let(:sprints_enabled) { [BoardFeature.new(raw: { 'feature' => 'jsw.agility.sprints', 'state' => 'ENABLED' })] }
    let(:sprints_disabled) { [BoardFeature.new(raw: { 'feature' => 'jsw.agility.sprints', 'state' => 'DISABLED' })] }

    it 'is true for a simple board without sprints' do
      board = described_class.new raw: simple_raw, possible_statuses: StatusCollection.new,
                                  features: sprints_disabled
      expect(board.team_managed_kanban?).to be true
    end

    it 'is false for a simple board with sprints enabled' do
      board = described_class.new raw: simple_raw, possible_statuses: StatusCollection.new,
                                  features: sprints_enabled
      expect(board.team_managed_kanban?).to be false
    end

    it 'is false for a non-simple board' do
      board = load_complete_sample_board
      expect(board.team_managed_kanban?).to be false
    end
  end

  context 'estimation_configuration' do
    it 'returns story points defaults when estimation section is absent' do
      board = load_complete_sample_board
      config = board.estimation_configuration
      expect(config.units).to eq :story_points
      expect(config.display_name).to eq 'Story Points'
    end

    it 'returns issue count configuration' do
      board = described_class.new raw: {
        'id' => 1,
        'type' => 'kanban',
        'columnConfig' => { 'columns' => [] },
        'estimation' => { 'type' => 'issueCount' }
      }, possible_statuses: StatusCollection.new
      config = board.estimation_configuration
      expect(config.units).to eq :issue_count
      expect(config.display_name).to eq 'Issue Count'
    end
  end

  context 'accumulated_status_ids_per_column' do
    it 'accumulates properly no columns' do
      raw = {
        'id' => 3,
        'self' => 'https://improvingflow.atlassian.net/rest/agile/1.0/board/3/configuration',
        'columnConfig' => {
          'columns' => []
        }
      }

      board = described_class.new raw: raw, possible_statuses: StatusCollection.new
      expect(board.accumulated_status_ids_per_column).to be_empty
    end

    it 'handles actual columns' do
      board = load_complete_sample_board
      expect(board.accumulated_status_ids_per_column).to eq [
        ['Ready', [10_002, 10_011, 3, 10_001]],
        ['In Progress', [10_002, 10_011, 3]],
        ['Review', [10_002, 10_011]],
        ['Done', [10_002]]
      ]
    end
  end

  context 'ensure_uniqueness_of_column_names' do
    let(:find_names) do
      lambda do |json|
        json.collect { |status| status['name'] }
      end
    end

    it 'ignores columns with no duplicates' do
      board = load_complete_sample_board
      raw = [
        { 'name' => 'Backlog' },
        { 'name' => 'Doing' }
      ]
      board.ensure_uniqueness_of_column_names! raw
      expect(find_names.call(raw)).to eq %w[Backlog Doing]
    end

    it 'Adjusts one duplicate' do
      board = load_complete_sample_board
      raw = [
        { 'name' => 'Backlog' },
        { 'name' => 'Backlog' }
      ]
      board.ensure_uniqueness_of_column_names! raw
      expect(find_names.call(raw)).to eq %w[Backlog Backlog-2]
    end

    it 'Handles name collisions' do
      board = load_complete_sample_board
      raw = [
        { 'name' => 'Backlog' },
        { 'name' => 'Backlog-2' },
        { 'name' => 'Backlog' }
      ]
      board.ensure_uniqueness_of_column_names! raw
      expect(find_names.call(raw)).to eq %w[Backlog Backlog-2 Backlog-3]
    end
  end

  it 'handles inspect' do
    expect(load_complete_sample_board.inspect).to eq(
      'Board(id: 1, name: "SP board", board_type: "kanban")'
    )
  end

  context 'scrum? and kanban? for simple boards' do
    let(:simple_raw) do
      {
        'id' => 1,
        'type' => 'simple',
        'columnConfig' => { 'columns' => [] }
      }
    end
    let(:sprints_enabled) { [BoardFeature.new(raw: { 'feature' => 'jsw.agility.sprints', 'state' => 'ENABLED' })] }
    let(:sprints_disabled) { [BoardFeature.new(raw: { 'feature' => 'jsw.agility.sprints', 'state' => 'DISABLED' })] }

    it 'is scrum when sprints feature is enabled' do
      board = described_class.new raw: simple_raw, possible_statuses: StatusCollection.new,
                                  features: sprints_enabled
      expect(board.scrum?).to be true
      expect(board.kanban?).to be false
    end

    it 'is kanban when sprints feature is disabled' do
      board = described_class.new raw: simple_raw, possible_statuses: StatusCollection.new,
                                  features: sprints_disabled
      expect(board.scrum?).to be false
      expect(board.kanban?).to be true
    end

    it 'is kanban when no features file is available' do
      board = described_class.new raw: simple_raw, possible_statuses: StatusCollection.new
      expect(board.scrum?).to be false
      expect(board.kanban?).to be true
    end
  end
end
