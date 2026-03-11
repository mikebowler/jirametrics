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
    let(:sprints_enabled) do
      { 'features' => [{ 'feature' => 'jsw.agility.sprints', 'state' => 'ENABLED' }] }
    end
    let(:sprints_disabled) do
      { 'features' => [{ 'feature' => 'jsw.agility.sprints', 'state' => 'DISABLED' }] }
    end

    it 'is scrum when sprints feature is enabled' do
      board = described_class.new raw: simple_raw, possible_statuses: StatusCollection.new,
                                  features_raw: sprints_enabled
      expect(board.scrum?).to be true
      expect(board.kanban?).to be false
    end

    it 'is kanban when sprints feature is disabled' do
      board = described_class.new raw: simple_raw, possible_statuses: StatusCollection.new,
                                  features_raw: sprints_disabled
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
