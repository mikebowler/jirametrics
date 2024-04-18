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
end
