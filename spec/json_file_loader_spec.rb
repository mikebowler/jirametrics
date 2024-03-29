# frozen_string_literal: true

require './spec/spec_helper'

describe JsonFileLoader do
  it 'should load json' do
    filename = make_test_filename 'jsonfileloader'
    begin
      File.write(filename, '{"a": "b"}')

      expect(JsonFileLoader.new.load(filename)).to eq({ 'a' => 'b' })
    ensure
      File.unlink filename
    end
  end
end
