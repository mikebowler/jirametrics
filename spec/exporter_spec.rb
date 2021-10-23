# frozen_string_literal: true

require './spec/spec_helper'

TARGET_PATH = 'spec/tmp/testdir'

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
  end

  context 'jira_config' do
    it 'should raise exception if file not found' do
      exporter = Exporter.new
      expect { exporter.jira_config 'not-found.json' }.to raise_error Errno::ENOENT
    end

    it 'should load config' do
      exporter = Exporter.new
      exporter.jira_config 'spec/testdata/jira-config.json'
      expect(exporter.jira_config['url']).to eq 'https://improvingflow.atlassian.net'
    end
  end
end
