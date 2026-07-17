# frozen_string_literal: true

require './spec/spec_helper'
require './spec/mock_file_system'

describe GithubGateway do
  let(:file_system) { MockFileSystem.new }
  let(:gateway) do
    described_class.new(
      repo: 'owner/repo',
      project_keys: %w[SP OTHER],
      file_system: file_system
    )
  end

  describe '#extract_issue_keys' do
    it 'extracts a key from the branch name' do
      pr = { 'headRefName' => 'SP-112-fix-validation', 'title' => '', 'body' => nil }
      expect(gateway.extract_issue_keys(pr)).to eq ['SP-112']
    end

    it 'extracts a key from the title when branch has none' do
      pr = { 'headRefName' => 'fix-validation', 'title' => 'Fix SP-112 bug', 'body' => nil }
      expect(gateway.extract_issue_keys(pr)).to eq ['SP-112']
    end

    it 'extracts a key from the body when not in branch or title' do
      pr = { 'headRefName' => 'fix-stuff', 'title' => 'Stuff', 'body' => 'Closes SP-112' }
      expect(gateway.extract_issue_keys(pr)).to eq ['SP-112']
    end

    it 'extracts multiple keys from different sources' do
      pr = { 'headRefName' => 'SP-112-fix', 'title' => 'Also fixes OTHER-5', 'body' => nil }
      expect(gateway.extract_issue_keys(pr)).to eq %w[SP-112 OTHER-5]
    end

    it 'deduplicates keys mentioned in multiple places' do
      pr = { 'headRefName' => 'SP-112-fix', 'title' => 'Fix SP-112', 'body' => 'See SP-112' }
      expect(gateway.extract_issue_keys(pr)).to eq ['SP-112']
    end

    it 'ignores keys for unknown projects' do
      pr = { 'headRefName' => 'UNKNOWN-99-fix', 'title' => '', 'body' => nil }
      allow(gateway).to receive(:commit_messages_for).and_return([])
      expect(gateway.extract_issue_keys(pr)).to be_empty
    end

    it 'does not match a project key embedded in a longer word' do
      pr = { 'headRefName' => 'NOTSP-112-fix', 'title' => '', 'body' => nil }
      allow(gateway).to receive(:commit_messages_for).and_return([])
      expect(gateway.extract_issue_keys(pr)).to be_empty
    end

    it 'extracts a key when the issue number is followed by an underscore' do
      pr = { 'headRefName' => 'fix/SP-112_fix-validation', 'title' => '', 'body' => nil }
      expect(gateway.extract_issue_keys(pr)).to eq ['SP-112']
    end

    it 'returns empty when no project keys are configured' do
      gateway = described_class.new(repo: 'owner/repo', project_keys: [], file_system: file_system)
      pr = { 'headRefName' => 'SP-112-fix', 'title' => '', 'body' => nil }
      expect(gateway.extract_issue_keys(pr)).to be_empty
    end

    it 'handles nil body gracefully' do
      pr = { 'headRefName' => 'SP-112-fix', 'title' => 'Title', 'body' => nil }
      expect { gateway.extract_issue_keys(pr) }.not_to raise_error
    end

    context 'when falling back to the commit message' do
      let(:pr_no_keys) { { 'number' => 99, 'headRefName' => 'fix-stuff', 'title' => 'Stuff', 'body' => nil } }

      it 'finds a key in a commit message headline when not in branch, title, or body' do
        allow(gateway).to receive(:commit_messages_for).with(99).and_return(['SP-112 fix stuff', ''])
        expect(gateway.extract_issue_keys(pr_no_keys)).to eq ['SP-112']
      end

      it 'finds a key buried in a commit message body' do
        allow(gateway).to receive(:commit_messages_for).with(99).and_return(
          ['refactor stuff', "This addresses SP-112\nSome other text"]
        )
        expect(gateway.extract_issue_keys(pr_no_keys)).to eq ['SP-112']
      end

      it 'does not call commit_messages_for when keys are already found' do
        pr = { 'number' => 99, 'headRefName' => 'SP-112-fix', 'title' => '', 'body' => nil }
        allow(gateway).to receive(:commit_messages_for)
        gateway.extract_issue_keys(pr)
        expect(gateway).not_to have_received(:commit_messages_for)
      end

      it 'returns empty when commit messages also contain no keys' do
        allow(gateway).to receive(:commit_messages_for).with(99).and_return(['unrelated commit', 'another one'])
        expect(gateway.extract_issue_keys(pr_no_keys)).to be_empty
      end

      it 'deduplicates keys found across multiple commit messages' do
        allow(gateway).to receive(:commit_messages_for).with(99).and_return(['SP-112 first', 'SP-112 second'])
        expect(gateway.extract_issue_keys(pr_no_keys)).to eq ['SP-112']
      end
    end
  end

  describe '#extract_reviews' do
    it 'includes APPROVED reviews' do
      reviews = [{ 'author' => { 'login' => 'alice' }, 'submittedAt' => '2026-01-14T15:00:00Z', 'state' => 'APPROVED' }]
      expect(gateway.extract_reviews(reviews)).to eq [
        { 'author' => 'alice', 'submitted_at' => '2026-01-14T15:00:00Z', 'state' => 'APPROVED' }
      ]
    end

    it 'includes CHANGES_REQUESTED reviews' do
      reviews = [
        { 'author' => { 'login' => 'bob' }, 'submittedAt' => '2026-01-11T10:00:00Z', 'state' => 'CHANGES_REQUESTED' }
    ]
      expect(gateway.extract_reviews(reviews)).to eq [
        { 'author' => 'bob', 'submitted_at' => '2026-01-11T10:00:00Z', 'state' => 'CHANGES_REQUESTED' }
      ]
    end

    it 'excludes COMMENTED reviews' do
      reviews = [
        { 'author' => { 'login' => 'carol' }, 'submittedAt' => '2026-01-12T09:00:00Z', 'state' => 'COMMENTED' }
      ]
      expect(gateway.extract_reviews(reviews)).to be_empty
    end

    it 'returns empty for no reviews' do
      expect(gateway.extract_reviews([])).to be_empty
    end
  end

  describe '#build_pr_data' do
    let(:raw_pr) do
      {
        'number' => 42,
        'url' => 'https://github.com/owner/repo/pull/42',
        'title' => 'Fix SP-112',
        'headRefName' => 'SP-112-fix-validation',
        'createdAt' => '2026-01-10T09:00:00Z',
        'closedAt' => '2026-01-14T16:30:00Z',
        'mergedAt' => '2026-01-14T16:30:00Z',
        'state' => 'MERGED',
        'body' => nil,
        'reviews' => [],
        'additions' => 120,
        'deletions' => 30,
        'changedFiles' => 5
      }
    end

    it 'builds a PullRequest for a matched PR' do
      result = gateway.build_pr_data(raw_pr)
      expect(result).to be_a PullRequest
      expect(result.number).to eq 42
      expect(result.repo).to eq 'owner/repo'
      expect(result.url).to eq 'https://github.com/owner/repo/pull/42'
      expect(result.title).to eq 'Fix SP-112'
      expect(result.branch).to eq 'SP-112-fix-validation'
      expect(result.opened_at).to eq Time.parse('2026-01-10T09:00:00Z')
      expect(result.closed_at).to eq Time.parse('2026-01-14T16:30:00Z')
      expect(result.merged_at).to eq Time.parse('2026-01-14T16:30:00Z')
      expect(result.state).to eq 'MERGED'
      expect(result.issue_keys).to eq ['SP-112']
      expect(result.reviews).to be_empty
      expect(result.additions).to eq 120
      expect(result.deletions).to eq 30
      expect(result.changed_files).to eq 5
      expect(result.lines_changed).to eq 150
    end

    it 'returns nil when no issue keys can be found' do
      raw_pr['headRefName'] = 'unrelated-branch'
      raw_pr['title'] = 'Unrelated change'
      allow(gateway).to receive(:commit_messages_for).and_return([])
      expect(gateway.build_pr_data(raw_pr)).to be_nil
    end

    it 'includes an open PR with no closed_at or merged_at' do
      raw_pr['state'] = 'OPEN'
      raw_pr['closedAt'] = nil
      raw_pr['mergedAt'] = nil
      result = gateway.build_pr_data(raw_pr)
      aggregate_failures do
        expect(result.state).to eq 'OPEN'
        expect(result.closed_at).to be_nil
        expect(result.merged_at).to be_nil
      end
    end
  end

  describe '#fetch_pull_requests' do
    let(:raw_prs) do
      [
        {
          'number' => 42, 'url' => 'https://github.com/owner/repo/pull/42',
          'title' => 'Fix SP-112', 'headRefName' => 'SP-112-fix',
          'createdAt' => '2026-01-10T09:00:00Z', 'closedAt' => '2026-01-14T16:30:00Z',
          'mergedAt' => '2026-01-14T16:30:00Z', 'state' => 'MERGED',
          'body' => nil, 'reviews' => [], 'additions' => 10, 'deletions' => 5, 'changedFiles' => 2
        },
        {
          'number' => 43, 'url' => 'https://github.com/owner/repo/pull/43',
          'title' => 'Unrelated', 'headRefName' => 'some-other-branch',
          'createdAt' => '2026-01-11T09:00:00Z', 'closedAt' => nil,
          'mergedAt' => nil, 'state' => 'OPEN',
          'body' => nil, 'reviews' => [], 'additions' => 0, 'deletions' => 0, 'changedFiles' => 0
        }
      ]
    end

    it 'returns only PRs that reference known project keys' do
      allow(gateway).to receive_messages(run_command: raw_prs, commit_messages_for: [])
      allow(gateway).to receive(:fetch_commits_batch).and_return({})
      results = gateway.fetch_pull_requests
      expect(results.size).to eq 1
      expect(results.first.number).to eq 42
    end

    it 'passes the since date to the gh command' do
      allow(gateway).to receive(:run_command) do |args|
        expect(args).to include('--search', 'updated:>=2026-01-01')
        []
      end
      gateway.fetch_pull_requests since: Date.parse('2026-01-01')
    end

    it 'omits the search flag when no since date given' do
      allow(gateway).to receive(:run_command) do |args|
        expect(args).not_to include('--search')
        []
      end
      gateway.fetch_pull_requests
    end

    it 'uses the shared cache to avoid duplicate GitHub requests for the same repo and since date' do
      cache = {}
      gateway1 = described_class.new(
        repo: 'owner/repo', project_keys: %w[SP], file_system: file_system, raw_pr_cache: cache
      )
      gateway2 = described_class.new(
        repo: 'owner/repo', project_keys: %w[OTHER], file_system: file_system, raw_pr_cache: cache
      )

      allow(gateway1).to receive(:run_command).and_return([])
      allow(gateway2).to receive(:run_command)

      gateway1.fetch_pull_requests
      gateway2.fetch_pull_requests

      expect(gateway2).not_to have_received(:run_command)
    end

    it 'makes separate requests for different repos even with a shared cache' do
      cache = {}
      gateway1 = described_class.new(
        repo: 'owner/repo1', project_keys: %w[SP], file_system: file_system, raw_pr_cache: cache
      )
      gateway2 = described_class.new(
        repo: 'owner/repo2', project_keys: %w[SP], file_system: file_system, raw_pr_cache: cache
      )

      allow(gateway1).to receive(:run_command).and_return([])
      allow(gateway2).to receive(:run_command).and_return([])

      gateway1.fetch_pull_requests
      gateway2.fetch_pull_requests

      expect(gateway2).to have_received(:run_command)
    end

    it 'caches commit-message fallback lookups across gateways sharing a cache for the same repo and PR' do
      cache = {}
      commits = { 'commits' => [{ 'messageHeadline' => 'SP-112 fix', 'messageBody' => '' }] }
      gateway1 = described_class.new(
        repo: 'owner/repo', project_keys: %w[SP], file_system: file_system, raw_pr_cache: cache
      )
      gateway2 = described_class.new(
        repo: 'owner/repo', project_keys: %w[SP], file_system: file_system, raw_pr_cache: cache
      )

      allow(gateway1).to receive(:run_command).and_return(commits)
      allow(gateway2).to receive(:run_command)

      expect(gateway1.send(:commit_messages_for, 99)).to eq ['SP-112 fix', '']
      expect(gateway2.send(:commit_messages_for, 99)).to eq ['SP-112 fix', '']
      expect(gateway2).not_to have_received(:run_command)
    end

    it 'does not let a cached commit lookup leak across different repos' do
      cache = {}
      gateway1 = described_class.new(
        repo: 'owner/repo1', project_keys: %w[SP], file_system: file_system, raw_pr_cache: cache
      )
      gateway2 = described_class.new(
        repo: 'owner/repo2', project_keys: %w[SP], file_system: file_system, raw_pr_cache: cache
      )

      allow(gateway1).to receive(:run_command).and_return({ 'commits' => [] })
      allow(gateway2).to receive(:run_command).and_return({ 'commits' => [] })

      gateway1.send(:commit_messages_for, 99)
      gateway2.send(:commit_messages_for, 99)

      expect(gateway2).to have_received(:run_command)
    end
  end

  context 'when batching commit-message fallbacks' do
    def raw_pr number:, title: 'Unrelated', branch: 'misc-branch', body: nil
      {
        'number' => number, 'url' => "https://github.com/owner/repo/pull/#{number}",
        'title' => title, 'headRefName' => branch, 'body' => body,
        'createdAt' => '2026-01-10T09:00:00Z', 'closedAt' => nil, 'mergedAt' => nil,
        'state' => 'OPEN', 'reviews' => [], 'additions' => 0, 'deletions' => 0, 'changedFiles' => 0
      }
    end

    def graphql_pr index:, headline:, total_count: nil
      nodes = [{ 'commit' => { 'messageHeadline' => headline, 'messageBody' => nil } }]
      ["pr#{index}", { 'commits' => { 'totalCount' => total_count || nodes.size, 'nodes' => nodes } }]
    end

    it 'fetches commits for all keyless PRs in a single graphql request, not one gh pr view each' do
      list = [raw_pr(number: 42, title: 'Fix SP-1', branch: 'SP-1'), raw_pr(number: 43), raw_pr(number: 44)]
      graphql = { 'data' => { 'repository' => [
        graphql_pr(index: 0, headline: 'SP-99 in commit'),
        graphql_pr(index: 1, headline: 'no key here')
      ].to_h } }
      allow(gateway).to receive(:run_command) do |args|
        args.first(2) == %w[api graphql] ? graphql : list
      end

      results = gateway.fetch_pull_requests

      aggregate_failures do
        expect(results.map(&:number)).to contain_exactly(42, 43)
        expect(gateway).to have_received(:run_command).with(array_including('api', 'graphql')).once
        expect(gateway).not_to have_received(:run_command).with(array_including('view'))
      end
    end

    it 'does not issue a graphql request when every PR already has keys in its fields' do
      allow(gateway).to receive(:run_command).and_return([raw_pr(number: 42, title: 'Fix SP-1', branch: 'SP-1')])

      gateway.fetch_pull_requests

      expect(gateway).not_to have_received(:run_command).with(array_including('graphql'))
    end

    it 'falls back to a single gh pr view when a PR has more commits than one page' do
      list = [raw_pr(number: 43)]
      graphql = { 'data' => { 'repository' => [
        graphql_pr(index: 0, headline: 'no key in first page', total_count: 5000)
      ].to_h } }
      allow(gateway).to receive(:run_command) do |args|
        if args.first(2) == %w[api graphql]
          graphql
        elsif args.first(2) == %w[pr view]
          { 'commits' => [{ 'messageHeadline' => 'SP-77 buried deep', 'messageBody' => nil }] }
        else
          list
        end
      end

      results = gateway.fetch_pull_requests

      aggregate_failures do
        expect(results.map(&:number)).to eq [43]
        expect(gateway).to have_received(:run_command).with(array_including('pr', 'view'))
      end
    end

    it 'builds the graphql query from a full repo URL' do
      url_gateway = described_class.new(
        repo: 'https://github.com/JANA-Technology/Lighthouse-TIMP-Backend.git',
        project_keys: %w[SP], file_system: file_system
      )
      captured = nil
      allow(url_gateway).to receive(:run_command) do |args|
        if args.first(2) == %w[api graphql]
          captured = args.last
          { 'data' => { 'repository' => {} } }
        else
          [raw_pr(number: 43)]
        end
      end
      allow(url_gateway).to receive(:commit_messages_for).and_return([])

      url_gateway.fetch_pull_requests

      aggregate_failures do
        expect(captured).to include('owner: "JANA-Technology"', 'name: "Lighthouse-TIMP-Backend"')
        expect(captured).to include('pr0: pullRequest(number: 43)')
      end
    end

    it 'splits large keyless sets into batches' do
      list = (1..65).map { |n| raw_pr(number: n) }
      graphql = { 'data' => { 'repository' => {} } }
      allow(gateway).to receive(:run_command) do |args|
        if args.first(2) == %w[api graphql]
          graphql
        elsif args.first(2) == %w[pr view]
          { 'commits' => [] }
        else
          list
        end
      end

      gateway.fetch_pull_requests

      expect(gateway).to have_received(:run_command).with(array_including('api', 'graphql'))
        .exactly((65.0 / GithubGateway::COMMIT_FETCH_BATCH_SIZE).ceil).times
    end
  end

  describe '#run_command' do
    it 'raises a helpful error when the gh CLI reports a SAML enforcement error' do
      success = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return(
        ['[]', 'GraphQL: Resource protected by organization SAML enforcement. ' \
               'You must grant your OAuth token access to this organization. (repository)', success]
      )

      expect { gateway.fetch_raw_pull_requests }.to raise_error(
        RuntimeError, /not authorized.*gh auth refresh/i
      )
    end

    it 'retries on transient HTTP 504 errors and succeeds' do
      failure = instance_double(Process::Status, success?: false)
      success = instance_double(Process::Status, success?: true)
      allow(gateway).to receive(:sleep)
      allow(Open3).to receive(:capture3)
        .and_return(['', 'HTTP 504: We could not respond in time.', failure],
                    ['[]', '', success])

      expect { gateway.fetch_raw_pull_requests }.not_to raise_error
      expect(Open3).to have_received(:capture3).twice
    end

    it 'raises after exhausting all retries on persistent transient errors' do
      failure = instance_double(Process::Status, success?: false)
      allow(gateway).to receive(:sleep)
      allow(Open3).to receive(:capture3).and_return(['', 'HTTP 504: timed out', failure])

      expect { gateway.fetch_raw_pull_requests }.to raise_error(RuntimeError, /GitHub CLI command failed/)
      expect(Open3).to have_received(:capture3).exactly(GithubGateway::MAX_RETRIES).times
    end

    it 'retries on stream errors and succeeds' do
      failure = instance_double(Process::Status, success?: false)
      success = instance_double(Process::Status, success?: true)
      allow(gateway).to receive(:sleep)
      allow(Open3).to receive(:capture3)
        .and_return(['', 'stream error: stream ID 1; CANCEL; received from peer', failure],
                    ['[]', '', success])

      expect { gateway.fetch_raw_pull_requests }.not_to raise_error
      expect(Open3).to have_received(:capture3).twice
    end

    it 'retries on unexpected end of JSON input and succeeds' do
      failure = instance_double(Process::Status, success?: false)
      success = instance_double(Process::Status, success?: true)
      allow(gateway).to receive(:sleep)
      allow(Open3).to receive(:capture3)
        .and_return(['', 'unexpected end of JSON input', failure],
                    ['[]', '', success])

      expect { gateway.fetch_raw_pull_requests }.not_to raise_error
      expect(Open3).to have_received(:capture3).twice
    end

    it 'logs elapsed time for the call' do
      success = instance_double(Process::Status, success?: true)
      allow(gateway).to receive(:monotonic_time).and_return(10.0, 12.34)
      allow(Open3).to receive(:capture3).and_return(['[]', '', success])

      gateway.fetch_raw_pull_requests
      expect(file_system.log_messages).to include('[diag] gh pr list call took 2.34s')
    end

    it 'does not retry on non-transient errors' do
      failure = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3).and_return(['', 'HTTP 404: Not Found', failure])

      expect { gateway.fetch_raw_pull_requests }.to raise_error(RuntimeError, /GitHub CLI command failed/)
      expect(Open3).to have_received(:capture3).once
    end
  end
end
