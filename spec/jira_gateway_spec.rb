# frozen_string_literal: true

describe JiraGateway do
  let(:file_system) { MockFileSystem.new }
  let(:gateway) do
    described_class.new(
      file_system: file_system,
      jira_config: { 'url' => 'https://example.com' },
      settings: { 'ignore_ssl_errors' => false }
    )
  end

  context 'make_curl_command' do
    it 'handles empty config' do
      gateway.load_jira_config({ 'url' => 'https://example.com' })

      expect(gateway.make_curl_command url: 'http://foo').to eq(
        'curl -L -s' \
        ' --request GET' \
        ' --header "Accept: application/json"' \
        ' --show-error --fail' \
        ' --url "http://foo"'
      )
    end

    it 'ignores SSL errors' do
      gateway.load_jira_config({ 'url' => 'https://example.com' })
      gateway.ignore_ssl_errors = true
      expect(gateway.make_curl_command url: 'http://foo').to eq(
        'curl -L -s -k' \
        ' --request GET' \
        ' --header "Accept: application/json"' \
        ' --show-error --fail' \
        ' --url "http://foo"'
      )
    end

    it 'works with personal_access_token' do
      gateway.load_jira_config({
        'url' => 'https://example.com',
        'personal_access_token' => 'yy'
      })
      expect(gateway.make_curl_command url: 'http://foo').to eq(
        'curl -L -s -H "Authorization: Bearer yy"' \
        ' --request GET' \
        ' --header "Accept: application/json"' \
        ' --show-error --fail' \
        ' --url "http://foo"'
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
      expected = 'curl -L -s' \
        ' --request GET' \
        ' --header "Accept: application/json"' \
        ' --show-error --fail' \
        ' --url "URL"'
      expect(gateway.make_curl_command(url: 'URL')).to eq expected
    end

    it 'generates with cookies' do
      gateway.load_jira_config({ 'url' => 'https://example.com', 'cookies' => { 'a' => 'b' } })
      expected = 'curl -L -s' \
        ' --cookie "a=b"' \
        ' --request GET' \
        ' --header "Accept: application/json"' \
        ' --show-error --fail' \
        ' --url "URL"'
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
        ' --show-error --fail' \
        ' --url "URL"'
      expect(gateway.make_curl_command(url: 'URL')).to eq expected
    end
  end

  context 'json_successful' do
    it 'succeeds for simple json' do
      json = { 'a' => 'b' }
      expect(gateway).to be_json_successful(json)
    end

    it 'fails for error' do
      json = { 'error' => 'foo' }
      expect(gateway).not_to be_json_successful(json)
    end

    it 'fails for errorMessage' do
      json = { 'errorMessage' => 'foo' }
      expect(gateway).not_to be_json_successful(json)
    end

    it 'fails for errorMessages' do
      json = { 'errorMessage' => ['foo'] }
      expect(gateway).not_to be_json_successful(json)
    end

    it 'fails for array of errorMessage' do
      # Seen this one from the status api
      json = ['errorMessage', 'Site temporarily unavailable']
      expect(gateway).not_to be_json_successful(json)
    end
  end
end
