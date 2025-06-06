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

  context 'fabricate_status_for' do
    it 'pulls category from historical statuses' do
      collection.historical_status_mappings['"walk":100'] = Status::Category.new name: 'movement', id: 101, key: 'new'
      collection.fabricate_status_for name: 'walk', id: 100
      expect(collection.find_by_id 100).to eq Status.new(
        name: 'walk', id: 100, category_name: 'movement', category_id: 101, category_key: 'new'
      )
    end

    it 'defaults to an in-progress status' do
      collection.fabricate_status_for name: 'walk', id: 100
      expect(collection.find_by_id 100).to eq Status.new(
        name: 'walk', id: 100, category_name: 'In Progress', category_id: 1001, category_key: 'indeterminate'
      )
    end
  end

  context 'find_all_by_name' do
    it 'finds nothing' do
      expect(collection.find_all_by_name 'e').to be_empty
    end

    it 'finds an exact match with only a name' do
      expect(collection.find_all_by_name 'c').to eq [status_c]
    end

    it 'finds two with same name' do
      status = Status.new(
        name: 'c', id: 30, category_name: 'In Progress', category_id: 1001, category_key: 'indeterminate'
      )
      collection << status
      expect(collection.find_all_by_name('c').sort).to eq [status_c, status]
    end

    it 'finds an exact match from a name:id pair' do
      expect(collection.find_all_by_name 'c:3').to eq [status_c]
    end

    it "finds a mismatch where are given an id that doesn't match the name" do
      expect { collection.find_all_by_name 'c:1' }.to raise_error(
        'Specified status ID of 1 does not match specified name "c". You might have meant one of these: ' \
          '["a":1, "b":2, "c":3, "d":4].'
      )
    end

    it 'finds from just an id' do
      expect(collection.find_all_by_name '3').to eq [status_c]
    end

    it 'fails to find an id that does not exist' do
      expect(collection.find_all_by_name '3333').to be_empty
    end
  end

  context 'find_all_categories_by_name' do
    it 'accepts symbol to search by key' do
      expect(collection.find_all_categories_by_name :new).to eq [status_a.category]
    end
  end
end
