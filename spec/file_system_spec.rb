# frozen_string_literal: true

require './spec/spec_helper'

describe FileSystem do
  it 'loads json' do
    filename = make_test_filename 'jsonfileloader'
    begin
      File.write(filename, '{"a": "b"}')

      expect(described_class.new.load_json(filename)).to eq({ 'a' => 'b' })
    ensure
      File.unlink filename
    end
  end

  it 'returns nil if file does not exist' do
    expect(described_class.new.load_json('file_that_does_not_exist', fail_on_error: false)).to be_nil
  end

  it 'raises error if not exist' do
    expect { described_class.new.load_json('file_that_does_not_exist', fail_on_error: true) }
      .to raise_error Errno::ENOENT
  end

  context 'compress' do
    it "doesn't change structures that are full" do
      input    = { a: 1, b: { d: 5, e: [4, 5, 6] } }
      expected = { a: 1, b: { d: 5, e: [4, 5, 6] } }
      expect(described_class.new.compress(input)).to eq expected
    end

    it 'collapses empty lists' do
      input    = { a: nil, b: { d: 5, e: [] } }
      expected = { b: { d: 5 } }
      expect(described_class.new.compress(input)).to eq expected
    end
  end
end
