# frozen_string_literal: true

require './spec/spec_helper'

describe JsonFileLoader do
  it 'loads json' do
    filename = make_test_filename 'jsonfileloader'
    begin
      File.write(filename, '{"a": "b"}')

      expect(described_class.new.load(filename)).to eq({ 'a' => 'b' })
    ensure
      File.unlink filename
    end
  end

  it 'returns nil if file does not exist' do
    expect(described_class.new.load('file_that_does_not_exist', fail_on_error: false)).to be_nil
  end

  it 'raises error if not exist' do
    expect { described_class.new.load('file_that_does_not_exist', fail_on_error: true) }
      .to raise_error Errno::ENOENT
  end
end
