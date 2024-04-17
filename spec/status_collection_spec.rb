# frozen_string_literal: true

require './spec/spec_helper'

describe StatusCollection do
  let(:status_a) { Status.new(name: 'a', id: 1, category_name: 'To Do', category_id: 1000) }
  let(:status_b) { Status.new(name: 'b', id: 2, category_name: 'In Progress', category_id: 1001) }
  let(:status_c) { Status.new(name: 'c', id: 3, category_name: 'In Progress', category_id: 1001) }
  let(:status_d) { Status.new(name: 'd', id: 4, category_name: 'Done', category_id: 1002) }
  let(:subject) do
    collection = StatusCollection.new
    collection << status_a
    collection << status_b
    collection << status_c
    collection << status_d

    collection
  end

  context 'todo' do
    it 'should handle empty collection' do
      expect(StatusCollection.new.todo).to be_empty
    end

    it 'should handle base query' do
      expect(subject.todo).to eq ['a']
    end

    it 'should handle single include by name' do
      expect(subject.todo including: 'c').to eq %w[a c]
    end

    it 'should handle single include by id' do
      expect(subject.todo including: 3).to eq %w[a c]
    end

    it 'should handle multiple include by name' do
      expect(subject.todo including: %w[c d]).to eq %w[a c d]
    end

    it 'should handle multiple include by id' do
      expect(subject.todo including: [3, 'd']).to eq %w[a c d]
    end

    it 'should handle single exclude by name' do
      expect(subject.in_progress excluding: 'c').to eq %w[b]
    end
  end

  context 'in progress' do
    it 'should handle two statuses' do
      expect(subject.in_progress).to eq %w[b c]
    end
  end

  context 'done' do
    it 'should handle one statuse' do
      expect(subject.done).to eq ['d']
    end
  end

  context 'expand_statuses' do
    # Most variations are covered by tests in other classes

    it 'should raise error when status not found' do
      expect { subject.expand_statuses [2000] }.to raise_error(
        'Status not found: 2000. Possible statuses are: "a":1, "b":2, "c":3, "d":4'
      )
    end

    it 'should yield when block passed and status not found' do
      actual_unknown_statuses = []
      subject.expand_statuses([2000]) do |unknown_status|
        actual_unknown_statuses << unknown_status
      end
      expect(actual_unknown_statuses).to eq [2000]
    end
  end
end
