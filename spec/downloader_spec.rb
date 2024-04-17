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
  let(:downloader) { Downloader.new(download_config: download_config).tap { |d| d.quiet_mode = true } }

  context 'Build curl command' do
    it 'should generate with url only' do
      downloader.load_jira_config({})
      expected = 'curl -s --request GET --header "Accept: application/json" --url "URL"'
      expect(downloader.make_curl_command(url: 'URL')).to eq expected
    end

    it 'should generate with cookies' do
      downloader.load_jira_config({ 'cookies' => { 'a' => 'b' } })
      expected = 'curl -s --cookie "a=b" --request GET --header "Accept: application/json" --url "URL"'
      expect(downloader.make_curl_command(url: 'URL')).to eq expected
    end

    it 'should generate with api-token' do
      downloader.load_jira_config({ 'email' => 'fred@flintstone', 'api_token' => 'bedrock' })
      expected = 'curl -s --user fred@flintstone:bedrock --request GET --header "Accept: application/json" --url "URL"'
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
    it 'should only pull deltas if we have a previous download' do
      downloader.metadata.clear
      downloader.metadata['date_end'] = Date.parse('2021-07-20')

      download_config.rolling_date_count 90
      today = Time.parse('2021-08-01')
      expected = 'filter=5 AND ((updated >= "2021-07-20 00:00" AND updated <= "2021-08-01 23:59") OR ' \
        '((status changed OR Sprint is not EMPTY) AND statusCategory != Done))'
      expect(downloader.make_jql(today: today, filter_id: 5)).to eql expected

      expect(downloader.start_date_in_query).to eq Date.parse('2021-07-20')
    end

    it 'should use the filter id in the board config' do
      download_config.rolling_date_count 90
      expected = 'filter=5 AND ((updated >= "2021-05-03 00:00" AND updated <= "2021-08-01 23:59") OR ' \
        '((status changed OR Sprint is not EMPTY) AND statusCategory != Done))'

      jql = downloader.make_jql(today: Time.parse('2021-08-01'), filter_id: 5)
      expect(jql).to eql expected
    end
  end

  context 'load_jira_config' do
    it 'should fail when api-key specified but not email' do
      expect do
        downloader.load_jira_config({
          'api_token' => 'xx'
        })
      end.to raise_error(
        'When specifying an api-token, you must also specify email'
      )
    end

    it 'should fail when api-key and personal-access-token are both specified' do
      expect do
        downloader.load_jira_config({
          'api_token' => 'xx',
          'email' => 'aa',
          'personal_access_token' => 'yy'
        })
      end.to raise_error(
        "You can't specify both an api-token and a personal-access-token. They don't work together."
      )
    end
  end

  context 'make_curl_command' do
    it 'should handle empty config' do
      downloader.load_jira_config({})

      expect(downloader.make_curl_command url: 'http://foo').to eq(
        %(curl -s --request GET --header "Accept: application/json" --url "http://foo")
      )
    end

    it 'should ignore SSL errors' do
      downloader.load_jira_config({})
      download_config.project_config.settings['ignore_ssl_errors'] = true
      expect(downloader.make_curl_command url: 'http://foo').to eq(
        %(curl -s -k --request GET --header "Accept: application/json" --url "http://foo")
      )
    end

    it 'work with personal_access_token' do
      downloader.load_jira_config({
        'personal_access_token' => 'yy'
      })
      expect(downloader.make_curl_command url: 'http://foo').to eq(
        %(curl -s -H "Authorization: Bearer yy" --request GET --header "Accept: application/json" --url "http://foo")
      )
    end
  end
end
