# frozen_string_literal: true

require './spec/spec_helper'

def mock_config
  config = ConfigBase.new file_prefix: nil, jql: ''
  config
end

describe Downloader do
  context "Build curl command" do
    it 'should generate with url only' do
      downloader = Downloader.new([mock_config])
      downloader.load_jira_config({})
      expected = "curl --request GET --header \"Accept: application/json\" --url \"URL\""
      expect(downloader.make_curl_command url: 'URL').to eq expected
    end

    it 'should generate with cookies' do
      downloader = Downloader.new([mock_config])
      downloader.load_jira_config({ 'cookies' => {"a" => "b"} })
      expected = "curl --cookie \"a=b\" --request GET --header \"Accept: application/json\" --url \"URL\""
      expect(downloader.make_curl_command url: 'URL').to eq expected
    end

    it 'should generate with api-token' do
      downloader = Downloader.new([mock_config])
      downloader.load_jira_config({ 'email' => 'fred@flintstone', 'api_token' => 'bedrock' })
      expected = "curl --user fred@flintstone:bedrock --request GET --header \"Accept: application/json\" --url \"URL\""
      expect(downloader.make_curl_command url: 'URL').to eq expected
    end
  end

  context "IO" do 
    it "should load json" do 
    downloader = Downloader.new([mock_config])
    filename = make_test_filename "downloader_write_json"
    begin
      downloader.write_json( { 'c' => 'd'}, filename)
      expect(File.read(filename)).to eq %({\n  "c": "d"\n})
    ensure
      File.unlink filename
    end
    end
  end        
end