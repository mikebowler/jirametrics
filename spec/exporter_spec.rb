# frozen_string_literal: true

require './spec/spec_helper'

TARGET_PATH = 'tmp/testdir'

describe Exporter do
  context 'target_path' do
    it 'should work with no file separator at end' do
      Dir.rmdir TARGET_PATH if Dir.exist? TARGET_PATH
      exporter = Exporter.new
      exporter.target_path TARGET_PATH
      expect(exporter.target_path).to eq "#{TARGET_PATH}/"
      expect(Dir).to exist(TARGET_PATH)
    end

    it 'should work with file separator at end' do
      Dir.rmdir TARGET_PATH if Dir.exist? TARGET_PATH
      exporter = Exporter.new
      exporter.target_path "#{TARGET_PATH}/"
      expect(exporter.target_path).to eq "#{TARGET_PATH}/"
      expect(Dir).to exist(TARGET_PATH)
    end

    # actually create target_path
    # works when path already exists
  end
end
