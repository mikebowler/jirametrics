# frozen_string_literal: true

describe GitHubGateway do
  let(:file_system) { MockFileSystem.new }
  let(:owner) { 'octocat' }
  let(:repo) { 'Hello-World' }
  let(:token) { 'ghp_test_token_12345' }
  let(:gateway) do
    described_class.new(
      file_system: file_system,
      owner: owner,
      repo: repo,
      token: token
    )
  end

  context 'initialization' do
    it 'requires file_system, owner, repo, and token' do
      expect do
        described_class.new(
          file_system: file_system,
          owner: owner,
          repo: repo,
          token: token
        )
      end.not_to raise_error
    end

    it 'fails when owner is missing' do
      expect do
        described_class.new(
          file_system: file_system,
          owner: nil,
          repo: repo,
          token: token
        )
      end.to raise_error('Must specify owner')
    end

    it 'fails when repo is missing' do
      expect do
        described_class.new(
          file_system: file_system,
          owner: owner,
          repo: nil,
          token: token
        )
      end.to raise_error('Must specify repo')
    end

    it 'fails when token is missing' do
      expect do
        described_class.new(
          file_system: file_system,
          owner: owner,
          repo: repo,
          token: nil
        )
      end.to raise_error('Must specify token')
    end
  end

  context 'make_curl_command' do
    it 'generates correct curl command for commits endpoint' do
      expected = 'curl -L -s' \
        ' -H "Authorization: token ghp_test_token_12345"' \
        ' --request GET' \
        ' --header "Accept: application/json"' \
        ' --show-error --fail' \
        ' --url "https://api.github.com/repos/octocat/Hello-World/commits"'
      expect(gateway.make_curl_command(url: 'https://api.github.com/repos/octocat/Hello-World/commits')).to eq expected
    end

    it 'handles pagination with page parameter' do
      url = 'https://api.github.com/repos/octocat/Hello-World/commits?page=2'
      expected = 'curl -L -s' \
        ' -H "Authorization: token ghp_test_token_12345"' \
        ' --request GET' \
        ' --header "Accept: application/json"' \
        ' --show-error --fail' \
        ' --url "https://api.github.com/repos/octocat/Hello-World/commits?page=2"'
      expect(gateway.make_curl_command(url: url)).to eq expected
    end

    it 'sanitizes token in log messages' do
      message = 'curl -H "Authorization: token ghp_test_token_12345"'
      expect(gateway.sanitize_message(message)).to eq('curl -H "Authorization: token [API_TOKEN]"')
    end
  end

  context 'get_commits' do
    it 'retrieves commits successfully' do
      commit_response = [
        {
          'sha' => 'abc123',
          'commit' => {
            'author' => {
              'name' => 'John Doe',
              'email' => 'john@example.com',
              'date' => '2024-01-01T12:00:00Z'
            },
            'message' => 'Initial commit',
            'url' => 'https://api.github.com/repos/octocat/Hello-World/commits/abc123'
          },
          'html_url' => 'https://github.com/octocat/Hello-World/commit/abc123',
          'author' => {
            'login' => 'johndoe',
            'id' => 1
          }
        }
      ]

      output = "HTTP/1.1 200 OK\r\n\r\n#{commit_response.to_json}"
      allow(gateway).to receive(:capture3).and_return(
        [output, '', MockStatus.new(exitstatus: 0)]
      )

      commits = gateway.get_commits

      expect(commits).to be_an(Array)
      expect(commits.length).to eq(1)
      expect(commits.first['sha']).to eq('abc123')
      expect(commits.first['commit']['message']).to eq('Initial commit')
    end

    it 'handles empty commit list' do
      output = "HTTP/1.1 200 OK\r\n\r\n#{[].to_json}"
      allow(gateway).to receive(:capture3).and_return(
        [output, '', MockStatus.new(exitstatus: 0)]
      )

      commits = gateway.get_commits

      expect(commits).to be_an(Array)
      expect(commits).to be_empty
    end

    it 'handles API errors' do
      error_response = {
        'message' => 'Not Found',
        'documentation_url' => 'https://docs.github.com/rest'
      }

      output = "HTTP/1.1 200 OK\r\n\r\n#{error_response.to_json}"
      allow(gateway).to receive(:capture3).and_return(
        [output, '', MockStatus.new(exitstatus: 0)]
      )

      expect { gateway.get_commits }.to raise_error(/Download failed/)
    end

    it 'handles curl command failures' do
      allow(gateway).to receive(:capture3).and_return(
        ['', 'curl: (22) The requested URL returned error: 404', MockStatus.new(exitstatus: 22)]
      )

      expect { gateway.get_commits }.to raise_error(/Failed call with exit status 22/)
    end

    it 'handles invalid JSON response' do
      output = "HTTP/1.1 200 OK\r\n\r\nnot json"
      allow(gateway).to receive(:capture3).and_return(
        [output, '', MockStatus.new(exitstatus: 0)]
      )

      expect { gateway.get_commits }.to raise_error(/Unable to parse results/)
    end
  end

  context 'get_all_commits with pagination' do
    it 'retrieves all commits across multiple pages' do
      page1_response = [
        { 'sha' => 'commit1', 'commit' => { 'message' => 'First commit' } },
        { 'sha' => 'commit2', 'commit' => { 'message' => 'Second commit' } }
      ]

      page2_response = [
        { 'sha' => 'commit3', 'commit' => { 'message' => 'Third commit' } }
      ]

      # Simulate curl output with headers and body
      page1_output = "HTTP/1.1 200 OK\r\n" \
        "Link: <https://api.github.com/repos/octocat/Hello-World/commits?page=2>; rel=\"next\"\r\n" \
        "\r\n" \
        "#{page1_response.to_json}"

      page2_output = "HTTP/1.1 200 OK\r\n" \
        "\r\n" \
        "#{page2_response.to_json}"

      allow(gateway).to receive(:capture3).and_return(
        [page1_output, '', MockStatus.new(exitstatus: 0)],
        [page2_output, '', MockStatus.new(exitstatus: 0)]
      )

      commits = gateway.get_all_commits

      expect(commits.length).to eq(3)
      expect(commits.map { |c| c['sha'] }).to eq(%w[commit1 commit2 commit3])
    end

    it 'handles single page of results' do
      page1_response = [
        { 'sha' => 'commit1', 'commit' => { 'message' => 'First commit' } }
      ]

      page1_output = "HTTP/1.1 200 OK\r\n" \
        "\r\n" \
        "#{page1_response.to_json}"

      allow(gateway).to receive(:capture3).and_return(
        [page1_output, '', MockStatus.new(exitstatus: 0)]
      )

      commits = gateway.get_all_commits

      expect(commits.length).to eq(1)
      expect(commits.first['sha']).to eq('commit1')
    end

    it 'handles pagination with multiple pages' do
      # Simulate 3 pages of results
      page1_output = "HTTP/1.1 200 OK\r\n" \
        "Link: <https://api.github.com/repos/octocat/Hello-World/commits?page=2>; rel=\"next\"\r\n" \
        "\r\n" \
        "#{[{ 'sha' => 'commit1' }].to_json}"

      page2_output = "HTTP/1.1 200 OK\r\n" \
        "Link: <https://api.github.com/repos/octocat/Hello-World/commits?page=3>; rel=\"next\"\r\n" \
        "\r\n" \
        "#{[{ 'sha' => 'commit2' }].to_json}"

      page3_output = "HTTP/1.1 200 OK\r\n" \
        "\r\n" \
        "#{[{ 'sha' => 'commit3' }].to_json}"

      allow(gateway).to receive(:capture3).and_return(
        [page1_output, '', MockStatus.new(exitstatus: 0)],
        [page2_output, '', MockStatus.new(exitstatus: 0)],
        [page3_output, '', MockStatus.new(exitstatus: 0)]
      )

      commits = gateway.get_all_commits

      expect(commits.length).to eq(3)
    end
  end

  context 'exec_and_parse_response' do
    it 'execs successfully and parses JSON' do
      json_response = { 'sha' => 'abc123', 'commit' => { 'message' => 'Test' } }
      output = "HTTP/1.1 200 OK\r\n\r\n#{json_response.to_json}"

      allow(gateway).to receive(:capture3).and_return(
        [output, '', MockStatus.new(exitstatus: 0)]
      )

      result = gateway.exec_and_parse_response(command: 'curl test', stdin_data: nil)

      expect(result).to eq(json_response)
      expect(file_system.log_messages).to include(match(/curl test/))
    end

    it 'execs with failure' do
      allow(gateway).to receive(:capture3).and_return(
        ['stdout', 'stderr', MockStatus.new(exitstatus: 1)]
      )

      expect { gateway.exec_and_parse_response(command: 'curl test', stdin_data: nil) }.to(
        raise_error(/Failed call with exit status 1/)
      )

      expect(file_system.log_messages).to include(match(/Failed call with exit status 1!/))
    end

    it 'handles empty stdout' do
      allow(gateway).to receive(:capture3).and_return(
        ['', '', MockStatus.new(exitstatus: 0)]
      )

      expect { gateway.exec_and_parse_response(command: 'curl test', stdin_data: nil) }.to(
        raise_error('no response from curl on stdout')
      )
    end
  end

  context 'json_successful' do
    it 'succeeds for valid commit array' do
      json = [{ 'sha' => 'abc123' }]
      expect(gateway).to be_json_successful(json)
    end

    it 'fails for GitHub API error message' do
      json = { 'message' => 'Not Found', 'documentation_url' => 'https://docs.github.com' }
      expect(gateway).not_to be_json_successful(json)
    end

    it 'succeeds for empty array' do
      json = []
      expect(gateway).to be_json_successful(json)
    end
  end

  context 'api_url' do
    it 'generates correct API URL' do
      expect(gateway.api_url).to eq('https://api.github.com/repos/octocat/Hello-World/commits')
    end
  end
end

