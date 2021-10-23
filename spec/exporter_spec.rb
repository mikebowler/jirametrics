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

  context 'project' do
    it 'should have target_path set' do
      exporter = Exporter.new
      exporter.jira_config 'spec/testdata/jira-config.json'
      expect { exporter.project }.to raise_error 'target_path was never set!'
    end

    it 'should have jira_config set' do
      exporter = Exporter.new
      exporter.target_path TARGET_PATH
      expect { exporter.project }.to raise_error 'jira_config not set'
    end

    it 'should create project_config' do
      exporter = Exporter.new
      exporter.target_path TARGET_PATH
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.project
      expect(exporter.project_configs.collect(&:target_path)).to eq ['spec/tmp/testdir/']
    end
  end
end
