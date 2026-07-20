# frozen_string_literal: true

require './spec/spec_helper'

describe Downloader do
  let(:download_config) do
    project = ProjectConfig.new(
      exporter: Exporter.new, target_path: 'spec/testdata/',
      jira_config: { 'url' => 'https://example.atlassian.net' }, block: nil
    )
    project.file_prefix 'sample'
    DownloadConfig.new project_config: project, block: nil
  end
  let(:file_system) { MockFileSystem.new }
  let(:meta_path) { 'spec/testdata/sample_meta.json' }
  let(:jira_gateway) do
    MockJiraGateway.new(
      file_system: file_system, jira_config: download_config.project_config.jira_config, settings: {}
    )
  end
  let(:downloader) do
    described_class.new(download_config: download_config, file_system: file_system, jira_gateway: jira_gateway)
  end

  describe '#load_metadata' do
    it 'does nothing when there is no metadata file' do
      allow(file_system).to receive(:load_json).with(meta_path, fail_on_error: false).and_return(nil)
      downloader.load_metadata
      expect(downloader.metadata).to eq({})
    end

    it 'loads values and parses ISO date strings when the format version is current' do
      allow(file_system).to receive(:load_json).with(meta_path, fail_on_error: false).and_return(
        'version' => Downloader::CURRENT_METADATA_VERSION,
        'earliest_date' => '2024-01-15',
        'label' => 'not a date'
      )
      downloader.load_metadata
      aggregate_failures do
        expect(downloader.metadata['earliest_date']).to eq Date.parse('2024-01-15')
        expect(downloader.metadata['label']).to eq 'not a date'
      end
    end

    it 'discards cached values from an older format version but still obeys no-download' do
      allow(file_system).to receive(:load_json).with(meta_path, fail_on_error: false).and_return(
        'version' => Downloader::CURRENT_METADATA_VERSION - 1,
        'earliest_date' => '2024-01-15',
        'no-download' => true
      )
      downloader.load_metadata
      aggregate_failures do
        expect(downloader.metadata).not_to have_key('earliest_date')
        expect(downloader.metadata['no-download']).to be true
      end
    end
  end
end
