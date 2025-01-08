# frozen_string_literal: true

require './spec/spec_helper'

describe StatusCollection do
  let(:status_a) { Status.new(name: 'a', id: 1, category_name: 'To Do', category_id: 1000, category_key: 'new') }
  let(:status_b) do
    Status.new(name: 'b', id: 2, category_name: 'In Progress', category_id: 1001, category_key: 'indeterminate')
  end
  let(:status_c) do
    Status.new(name: 'c', id: 3, category_name: 'In Progress', category_id: 1001, category_key: 'indeterminate')
  end
  let(:status_d) { Status.new(name: 'd', id: 4, category_name: 'Done', category_id: 1002, category_key: 'done') }
  let(:collection) do
    collection = described_class.new
    collection << status_a
    collection << status_b
    collection << status_c
    collection << status_d

    collection
  end

  it 'inspects as string' do
    expect(collection.inspect).to eq(
      'StatusCollection["a":1, "b":2, "c":3, "d":4]'
    )
  end

  it 'converts to string' do
    expect(collection.to_s).to eq(
      '["a":1, "b":2, "c":3, "d":4]'
    )
  end
end
