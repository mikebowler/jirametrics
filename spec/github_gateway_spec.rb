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

  context 'extract_issue_keys' do
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
      expect(gateway.extract_issue_keys(pr)).to be_empty
    end

    it 'does not match a project key embedded in a longer word' do
      pr = { 'headRefName' => 'NOTSP-112-fix', 'title' => '', 'body' => nil }
      expect(gateway.extract_issue_keys(pr)).to be_empty
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
  end

  context 'extract_reviews' do
    it 'includes APPROVED reviews' do
      reviews = [{ 'author' => { 'login' => 'alice' }, 'submittedAt' => '2026-01-14T15:00:00Z', 'state' => 'APPROVED' }]
      expect(gateway.extract_reviews(reviews)).to eq [
        { 'author' => 'alice', 'submitted_at' => '2026-01-14T15:00:00Z', 'state' => 'APPROVED' }
      ]
    end

    it 'includes CHANGES_REQUESTED reviews' do
      reviews = [{ 'author' => { 'login' => 'bob' }, 'submittedAt' => '2026-01-11T10:00:00Z', 'state' => 'CHANGES_REQUESTED' }]
      expect(gateway.extract_reviews(reviews)).to eq [
        { 'author' => 'bob', 'submitted_at' => '2026-01-11T10:00:00Z', 'state' => 'CHANGES_REQUESTED' }
      ]
    end

    it 'excludes COMMENTED reviews' do
      reviews = [{ 'author' => { 'login' => 'carol' }, 'submittedAt' => '2026-01-12T09:00:00Z', 'state' => 'COMMENTED' }]
      expect(gateway.extract_reviews(reviews)).to be_empty
    end

    it 'returns empty for no reviews' do
      expect(gateway.extract_reviews([])).to be_empty
    end
  end

  context 'build_pr_data' do
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
        'reviews' => []
      }
    end

    it 'builds the correct hash for a matched PR' do
      expect(gateway.build_pr_data(raw_pr)).to eq(
        'number'     => 42,
        'repo'       => 'owner/repo',
        'url'        => 'https://github.com/owner/repo/pull/42',
        'title'      => 'Fix SP-112',
        'branch'     => 'SP-112-fix-validation',
        'opened_at'  => '2026-01-10T09:00:00Z',
        'closed_at'  => '2026-01-14T16:30:00Z',
        'merged_at'  => '2026-01-14T16:30:00Z',
        'state'      => 'MERGED',
        'issue_keys' => ['SP-112'],
        'reviews'    => []
      )
    end

    it 'returns nil when no issue keys can be found' do
      raw_pr['headRefName'] = 'unrelated-branch'
      raw_pr['title'] = 'Unrelated change'
      expect(gateway.build_pr_data(raw_pr)).to be_nil
    end

    it 'includes an open PR with no closed_at or merged_at' do
      raw_pr['state'] = 'OPEN'
      raw_pr['closedAt'] = nil
      raw_pr['mergedAt'] = nil
      result = gateway.build_pr_data(raw_pr)
      expect(result['state']).to eq 'OPEN'
      expect(result['closed_at']).to be_nil
      expect(result['merged_at']).to be_nil
    end
  end

  context 'fetch_pull_requests' do
    let(:raw_prs) do
      [
        {
          'number' => 42, 'url' => 'https://github.com/owner/repo/pull/42',
          'title' => 'Fix SP-112', 'headRefName' => 'SP-112-fix',
          'createdAt' => '2026-01-10T09:00:00Z', 'closedAt' => '2026-01-14T16:30:00Z',
          'mergedAt' => '2026-01-14T16:30:00Z', 'state' => 'MERGED',
          'body' => nil, 'reviews' => []
        },
        {
          'number' => 43, 'url' => 'https://github.com/owner/repo/pull/43',
          'title' => 'Unrelated', 'headRefName' => 'some-other-branch',
          'createdAt' => '2026-01-11T09:00:00Z', 'closedAt' => nil,
          'mergedAt' => nil, 'state' => 'OPEN',
          'body' => nil, 'reviews' => []
        }
      ]
    end

    it 'returns only PRs that reference known project keys' do
      allow(gateway).to receive(:run_command).and_return(raw_prs)
      results = gateway.fetch_pull_requests
      expect(results.size).to eq 1
      expect(results.first['number']).to eq 42
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
  end
end
