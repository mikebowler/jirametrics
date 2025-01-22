# frozen_string_literal: true

require './spec/spec_helper'

TARGET_PATH = 'spec/tmp/testdir'

describe Exporter do
  let(:file_system) do
    MockFileSystem.new.tap do |fs|
      fs.when_loading file: 'spec/testdata/jira-config.json', json: :not_mocked
    end
  end
  let(:exporter) { described_class.new file_system: file_system }

  context 'target_path' do
    it 'works with no file separator at end' do
      Dir.rmdir TARGET_PATH if File.exist? TARGET_PATH
      exporter.target_path TARGET_PATH
      expect(exporter.target_path).to eq "#{TARGET_PATH}/"
      expect(Dir).to exist(TARGET_PATH)
    end

    it 'works with file separator at end' do
      Dir.rmdir TARGET_PATH if File.exist? TARGET_PATH
      exporter.target_path "#{TARGET_PATH}/"
      expect(exporter.target_path).to eq "#{TARGET_PATH}/"
      expect(Dir).to exist(TARGET_PATH)
    end
  end

  context 'jira_config' do
    it 'raises exception if file not found' do
      expect { exporter.jira_config 'not-found.json' }.to raise_error(
        'Unable to load Jira configuration file and cannot continue: "not-found.json"'
      )
      expect(exporter.file_system.log_messages).to be_empty
    end

    it 'loads config' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      expect(exporter.jira_config['url']).to eq 'https://improvingflow.atlassian.net'
    end

    it 'strips trailing slash from url' do
      exporter.file_system = MockFileSystem.new
      exporter.file_system.when_loading file: 'jira-config.json', json: { 'url' => 'foo/' }
      exporter.jira_config 'jira-config.json'
      expect(exporter.jira_config['url']).to eq 'foo'
    end
  end

  context 'project' do
    it 'has jira_config set' do
      exporter.target_path TARGET_PATH
      expect { exporter.project }.to raise_error 'jira_config not set'
    end

    it 'creates project_config' do
      exporter.target_path TARGET_PATH
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.project
      expect(exporter.project_configs.collect(&:target_path)).to eq ['spec/tmp/testdir/']
    end
  end

  context 'holiday_dates' do
    it 'allows simple dates' do
      expect(exporter.holiday_dates '2022-02-03').to eq([Date.parse('2022-02-03')])
    end

    it 'allows ranges' do
      expect(exporter.holiday_dates '2022-12-24..2022-12-26').to eq(
        [Date.parse('2022-12-24'), Date.parse('2022-12-25'), Date.parse('2022-12-26')]
      )
    end

    it 'initializes dates correctly' do
      # This seems like a wierd thing to test for but it was causing exceptions at one point
      expect(exporter.holiday_dates).to be_empty
    end
  end

  context 'each_project_config' do
    it 'matches all projects' do
      exporter.instance_variable_set :@jira_config, {}

      exporter.project name: 'action'
      exporter.project name: 'burrow'
      actual = []
      exporter.each_project_config name_filter: '*' do |project|
        actual << project.name
      end
      expect(actual).to eq %w[action burrow]
    end

    it 'filters by project name' do
      exporter.instance_variable_set :@jira_config, {}

      exporter.project name: 'action'
      exporter.project name: 'burrow'
      actual = []
      exporter.each_project_config name_filter: 'a*' do |project|
        actual << project.name
      end
      expect(actual).to eq %w[action]
    end
  end

  context 'download' do
    it 'fails if download block is missing' do
      exporter.jira_config 'spec/testdata/jira-config.json'
      exporter.project name: 'foo'
      expect { exporter.download name_filter: '*' }.to raise_error(
        'Project "foo" is missing a download section in the config. That is required in order to download'
      )
    end
  end
end
