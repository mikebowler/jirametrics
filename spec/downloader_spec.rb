# frozen_string_literal: true

require './spec/spec_helper'

def mock_download_config
  exporter = Exporter.new
  project = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
  project.file_prefix 'sample'
  project.status_category_mapping status: 'Backlog', category: 'ready'
  project.status_category_mapping status: 'Selected for Development', category: 'ready'
  project.status_category_mapping status: 'In Progress', category: 'in-flight'
  project.status_category_mapping status: 'Review', category: 'in-flight'
  project.status_category_mapping status: 'Done', category: 'finished'

  DownloadConfig.new project_config: project, block: nil
end

describe Downloader do
  let(:download_config) { mock_download_config }
  let(:downloader) { Downloader.new(download_config: download_config) }

  context 'Build curl command' do
    it 'should generate with url only' do
      downloader.load_jira_config({})
      expected = 'curl --request GET --header "Accept: application/json" --url "URL"'
      expect(downloader.make_curl_command(url: 'URL')).to eq expected
    end

    it 'should generate with cookies' do
      downloader.load_jira_config({ 'cookies' => { 'a' => 'b' } })
      expected = 'curl --cookie "a=b" --request GET --header "Accept: application/json" --url "URL"'
      expect(downloader.make_curl_command(url: 'URL')).to eq expected
    end

    it 'should generate with api-token' do
      downloader.load_jira_config({ 'email' => 'fred@flintstone', 'api_token' => 'bedrock' })
      expected = 'curl --user fred@flintstone:bedrock --request GET --header "Accept: application/json" --url "URL"'
      expect(downloader.make_curl_command(url: 'URL')).to eq expected
    end
  end

  context 'IO' do
    it 'should load json' do
      filename = make_test_filename 'downloader_write_json'
      begin
        downloader.write_json({ 'c' => 'd' }, filename)
        expect(File.read(filename)).to eq %({\n  "c": "d"\n})
      ensure
        File.unlink filename
      end
    end
  end

  context 'make_jql' do
    it 'makes from project' do
      download_config.project_key 'a'
      expect(downloader.make_jql).to eql 'project="a"'
    end

    it 'makes from project and rolling date count' do
      download_config.rolling_date_count 90
      today = DateTime.parse('2021-08-01')
      expected = '((status changed AND resolved = null) OR ' \
        '(status changed DURING ("2021-05-03 00:00","2021-08-01 23:59")))'
      expect(downloader.make_jql(today: today)).to eql expected
    end

    it 'makes from filter' do
      download_config.filter_name 'a'
      expect(downloader.make_jql).to eql 'filter="a"'
    end

    it 'makes from jql' do
      download_config.jql 'project=foo'
      expect(downloader.make_jql).to eql 'project=foo'
    end

    it 'throws exception when everything nil' do
      expect { downloader.make_jql }.to raise_error(/Couldn't make JQL/)
    end

    it 'should only pull deltas if we have a previous download' do
      downloader.metadata.clear
      downloader.metadata['date_end'] = Date.parse('2021-07-20')

      download_config.rolling_date_count 90
      today = DateTime.parse('2021-08-01')
      expected = '((status changed AND resolved = null) OR ' \
        '(status changed DURING ("2021-07-20 00:00","2021-08-01 23:59")))'
      expect(downloader.make_jql(today: today)).to eql expected

      expect(downloader.start_date_in_query).to eq Date.parse('2021-07-20')
    end
  end
end
