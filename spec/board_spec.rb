# frozen_string_literal: true

require './spec/spec_helper'

describe Board do
  context 'url' do
    it 'should fabricate url' do
      board = Board.new raw: {
        'id' => 3,
        'self' => 'https://improvingflow.atlassian.net/rest/agile/1.0/board/3/configuration',
        'columnConfig' => {
          'columns' => []
        }

      }
      expect(board.url).to eq('https://improvingflow.atlassian.net/secure/RapidBoard.jspa?rapidView=3')
    end

    it 'should throw exception if URL cannot be fabricated' do
      board = Board.new raw: {
        'id' => 3,
        'self' => 'random string',
        'columnConfig' => {
          'columns' => []
        }

      }
      expect { board.url }.to raise_error 'Cannot parse self: "random string"'
    end
  end
end
