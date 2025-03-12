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

      board = Board.new raw: raw, possible_statuses: StatusCollection.new
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

  context 'estimation fields', :focus do
    let(:board) { load_complete_sample_board }

    it 'returns default values' do
      expect(board.estimation).to eq({
        display_name: 'Story Points',
        units: :story_points
      })
    end

    it 'returns for field type estimation' do
      board.raw['estimation'] = {
        'type' => 'field',
        'field' => {
          'fieldId' => 'customfield_123',
          'displayName' => 'Story-Punkte'
        }
      }

      expect(board.estimation).to eq({
        display_name: 'Story-Punkte',
        field_id: 'customfield_123',
        units: :story_points
      })
    end

    it 'returns seconds' do
      board.raw['estimation'] = {
        'type' => 'field',
        'field' => {
          'fieldId' => 'timeoriginalestimate',
          'displayName' => 'Original estimate'
        }
      }

      expect(board.estimation).to eq({
        display_name: 'Original estimate',
        field_id: 'timeoriginalestimate',
        units: :seconds
      })
    end

    it 'returns seconds' do
      board.raw['estimation'] = {
        'type' => 'issueCount'
      }

      expect(board.estimation).to eq({
        display_name: 'Issue Count',
        units: :issue_count
      })
    end
  end
end
