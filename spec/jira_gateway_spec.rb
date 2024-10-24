# frozen_string_literal: true

describe JiraGateway do
  let(:file_system) { FileSystem.new }
  let(:gateway) { described_class.new file_system: file_system }

  context 'make_curl_command' do
    it 'handles empty config' do
      gateway.load_jira_config({ 'url' => 'https://example.com' })

      expect(gateway.make_curl_command url: 'http://foo').to eq(
        %(curl -L -s --request GET --header "Accept: application/json" --url "http://foo")
      )
    end

    it 'ignores SSL errors' do
      gateway.load_jira_config({ 'url' => 'https://example.com' })
      gateway.ignore_ssl_errors = true
      expect(gateway.make_curl_command url: 'http://foo').to eq(
        %(curl -L -s -k --request GET --header "Accept: application/json" --url "http://foo")
      )
    end

    it 'works with personal_access_token' do
      gateway.load_jira_config({
        'url' => 'https://example.com',
        'personal_access_token' => 'yy'
      })
      expect(gateway.make_curl_command url: 'http://foo').to eq(
        %(curl -L -s -H "Authorization: Bearer yy" --request GET --header "Accept: application/json" --url "http://foo")
      )
    end
  end

  context 'load_jira_config' do
    it 'fails when api-key specified but not email' do
      expect do
        gateway.load_jira_config({
          'url' => 'https://example.com',
          'api_token' => 'xx'
        })
      end.to raise_error(
        'When specifying an api-token, you must also specify email'
      )
    end

    it 'fails when api-key and personal-access-token are both specified' do
      expect do
        gateway.load_jira_config({
          'url' => 'https://example.com',
          'api_token' => 'xx',
          'email' => 'aa',
          'personal_access_token' => 'yy'
        })
      end.to raise_error(
        "You can't specify both an api-token and a personal-access-token. They don't work together."
      )
    end

    it 'fails when url not provided' do
      expect do
        gateway.load_jira_config({})
      end.to raise_error(
        'Must specify URL in config'
      )
    end
  end

  context 'Build curl command' do
    it 'generates with url only' do
      gateway.load_jira_config({ 'url' => 'https://example.com' })
      expected = 'curl -L -s --request GET --header "Accept: application/json" --url "URL"'
      expect(gateway.make_curl_command(url: 'URL')).to eq expected
    end

    it 'generates with cookies' do
      gateway.load_jira_config({ 'url' => 'https://example.com', 'cookies' => { 'a' => 'b' } })
      expected = 'curl -L -s --cookie "a=b" --request GET --header "Accept: application/json" --url "URL"'
      expect(gateway.make_curl_command(url: 'URL')).to eq expected
    end

    it 'generates with api-token' do
      gateway.load_jira_config(
        { 'url' => 'https://example.com', 'email' => 'fred@flintstone', 'api_token' => 'bedrock' }
      )
      expected = 'curl -L -s' \
        ' --user fred@flintstone:bedrock' \
        ' --request GET' \
        ' --header "Accept: application/json"' \
        ' --url "URL"'
      expect(gateway.make_curl_command(url: 'URL')).to eq expected
    end
  end

  context 'call_url' do
    it 'adds detail to exception when unable to parse result' do
      def gateway.call_command _command
        'foo'
      end
      gateway.load_jira_config({ 'url' => 'https://example.com' })
      expect { gateway.call_url relative_url: 'foo' }.to raise_error(
        "Error \"unexpected token at 'foo'\" when parsing result: \"foo\""
      )
    end
  end
end
