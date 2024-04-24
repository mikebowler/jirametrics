# frozen_string_literal: true

require './spec/spec_helper'

describe StatusCollection do
  let(:status_a) { Status.new(name: 'a', id: 1, category_name: 'To Do', category_id: 1000) }
  let(:status_b) { Status.new(name: 'b', id: 2, category_name: 'In Progress', category_id: 1001) }
  let(:status_c) { Status.new(name: 'c', id: 3, category_name: 'In Progress', category_id: 1001) }
  let(:status_d) { Status.new(name: 'd', id: 4, category_name: 'Done', category_id: 1002) }
  let(:collection) do
    collection = described_class.new
    collection << status_a
    collection << status_b
    collection << status_c
    collection << status_d

    collection
  end

  context 'todo' do
    it 'handles empty collection' do
      expect(described_class.new.todo).to be_empty
    end

    it 'handles base query' do
      expect(collection.todo).to eq ['a']
    end

    it 'handles single include by name' do
      expect(collection.todo including: 'c').to eq %w[a c]
    end

    it 'handles single include by id' do
      expect(collection.todo including: 3).to eq %w[a c]
    end

    it 'handles multiple include by name' do
      expect(collection.todo including: %w[c d]).to eq %w[a c d]
    end

    it 'handles multiple include by id' do
      expect(collection.todo including: [3, 'd']).to eq %w[a c d]
    end

    it 'handles single exclude by name' do
      expect(collection.in_progress excluding: 'c').to eq %w[b]
    end
  end

  context 'in progress' do
    it 'handles two statuses' do
      expect(collection.in_progress).to eq %w[b c]
    end
  end

  context 'done' do
    it 'handles one statuse' do
      expect(collection.done).to eq ['d']
    end
  end

  context 'expand_statuses' do
    # Most variations are covered by tests in other classes

    it 'raises error when status not found' do
      expect { collection.expand_statuses [2000] }.to raise_error(
        'Status not found: "2000". Possible statuses are: "a":1, "b":2, "c":3, "d":4'
      )
    end

    it 'yields when block passed and status not found' do
      actual_unknown_statuses = []
      collection.expand_statuses([2000]) do |unknown_status|
        actual_unknown_statuses << unknown_status
      end
      expect(actual_unknown_statuses).to eq [2000]
    end
  end
end
