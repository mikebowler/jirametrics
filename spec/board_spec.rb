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

      }
      expect(board.url).to eq('https://improvingflow.atlassian.net/secure/RapidBoard.jspa?rapidView=3')
    end

    it 'throws exception if URL cannot be fabricated' do
      board = described_class.new raw: {
        'id' => 3,
        'self' => 'random string',
        'columnConfig' => {
          'columns' => []
        }
      }
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
      }
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
      }
      expect(board.project_id).to eq 2
    end
  end
end
