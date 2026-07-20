# frozen_string_literal: true

require 'open3'
require 'json'

class GithubGateway
  attr_reader :repo

  TRANSIENT_ERROR_PATTERNS = (
    [429, 500, 502, 503, 504].map { |code| "HTTP #{code}" } +
    ['stream error:', 'unexpected end of JSON input']
  ).freeze
  MAX_RETRIES = 3
  REVIEW_STATES = %w[APPROVED CHANGES_REQUESTED].freeze

  # How many keyless PRs to request commits for in a single graphql call, and how many commits
  # to pull per PR. Kept bounded so node counts stay well under GitHub's graphql node limit.
  COMMIT_FETCH_BATCH_SIZE = 30
  MAX_COMMITS_PER_PR = 100

  def initialize repo:, project_keys:, file_system:, raw_pr_cache: {}
    @repo = repo
    @project_keys = project_keys
    @file_system = file_system
    @raw_pr_cache = raw_pr_cache
    @issue_key_pattern = build_issue_key_pattern
  end

  def fetch_pull_requests since: nil
    raw_prs = @raw_pr_cache[[@repo, since]] ||= fetch_raw_pull_requests(since: since)
    prefetch_commit_messages(raw_prs)
    raw_prs.filter_map { |pr| build_pr_data(pr) }
  end

  def fetch_raw_pull_requests since: nil
    # NOTE: 'commits' is intentionally excluded — including it triggers GitHub's GraphQL node
    # limit (authors sub-connection × PRs × commits exceeds 500,000 nodes). Branch name,
    # title, and body are sufficient for issue key extraction in the vast majority of cases.
    json_fields = %w[number title body headRefName createdAt closedAt mergedAt
                     url state reviews additions deletions changedFiles].join(',')
    args = ['pr', 'list', '--state', 'all', '--limit', '5000', '--json', json_fields]
    args += ['--repo', @repo]
    args += ['--search', "updated:>=#{since}"] if since

    @file_system.log "  Downloading pull requests from #{@repo}", also_write_to_stderr: true
    run_command(args)
  end

  def build_pr_data raw_pr
    issue_keys = extract_issue_keys(raw_pr)
    return nil if issue_keys.empty?

    PullRequest.new(raw: {
      'number'     => raw_pr['number'],
      'repo'       => @repo,
      'url'        => raw_pr['url'],
      'title'      => raw_pr['title'],
      'branch'     => raw_pr['headRefName'],
      'opened_at'  => raw_pr['createdAt'],
      'closed_at'  => raw_pr['closedAt'],
      'merged_at'  => raw_pr['mergedAt'],
      'state'      => raw_pr['state'],
      'issue_keys'    => issue_keys,
      'reviews'       => extract_reviews(raw_pr['reviews'] || []),
      'additions'     => raw_pr['additions'],
      'deletions'     => raw_pr['deletions'],
      'changed_files' => raw_pr['changedFiles']
    })
  end

  def extract_issue_keys raw_pr
    return [] if @issue_key_pattern.nil?

    keys = keys_from_text_fields(raw_pr)
    return keys unless keys.empty?

    commit_messages_for(raw_pr['number']).flat_map { |msg| msg.scan(@issue_key_pattern) }.uniq
  end

  def keys_from_text_fields raw_pr
    sources = [raw_pr['headRefName'], raw_pr['title'], raw_pr['body']]
    sources.compact.flat_map { |s| s.scan(@issue_key_pattern) }.uniq
  end

  def extract_reviews raw_reviews
    raw_reviews
      .select { |r| REVIEW_STATES.include?(r['state']) }
      .map do |r|
        {
          'author'       => r.dig('author', 'login'),
          'submitted_at' => r['submittedAt'],
          'state'        => r['state']
        }
      end
  end

  private

  # Pre-populate the shared commit cache for every PR with no key in its branch/title/body, using
  # batched graphql requests instead of one "gh pr view" per PR. build_pr_data -> commit_messages_for
  # then reads straight from the cache for those PRs (no per-PR network call). Any PR the batch can't
  # fully cover (more commits than one page, or absent from the response) is left uncached so the
  # single-PR fallback in commit_messages_for fills it in.
  def prefetch_commit_messages raw_prs
    return if @issue_key_pattern.nil?

    numbers = raw_prs
      .select { |raw_pr| keys_from_text_fields(raw_pr).empty? }
      .map { |raw_pr| raw_pr['number'] }
      .reject { |number| @raw_pr_cache.key?([@repo, :commits, number]) }

    numbers.each_slice(COMMIT_FETCH_BATCH_SIZE) do |batch|
      fetch_commits_batch(batch).each do |number, messages|
        @raw_pr_cache[[@repo, :commits, number]] = messages
      end
    end
  end

  def fetch_commits_batch numbers
    owner, name = owner_and_name
    aliases = numbers.each_with_index.map do |number, index|
      "pr#{index}: pullRequest(number: #{number}) " \
        "{ commits(first: #{MAX_COMMITS_PER_PR}) { totalCount nodes { commit { messageHeadline messageBody } } } }"
    end
    query = %(query { repository(owner: "#{owner}", name: "#{name}") { #{aliases.join(' ')} } })
    result = run_command(['api', 'graphql', '-f', "query=#{query}"])
    parse_commits_batch result: result, numbers: numbers
  end

  def parse_commits_batch result:, numbers:
    repository = result.dig('data', 'repository') || {}
    messages_by_number = {}
    numbers.each_with_index do |number, index|
      commits = repository.dig("pr#{index}", 'commits')
      next if commits.nil?

      nodes = commits['nodes'] || []
      # Skip caching when the PR has more commits than this page covers, so the single-PR
      # fallback fetches the complete set rather than us caching a partial answer.
      next if commits['totalCount'] && commits['totalCount'] > nodes.size

      messages_by_number[number] = nodes.flat_map do |node|
        commit = node['commit'] || {}
        [commit['messageHeadline'], commit['messageBody']].compact
      end
    end
    messages_by_number
  end

  def owner_and_name
    # @repo may be a full URL (https://github.com/owner/name.git) or an owner/name slug.
    @repo.sub(%r{\Ahttps?://[^/]+/}, '').delete_suffix('.git').split('/', 2)
  end

  def commit_messages_for pr_number
    # Cached in the shared per-run cache (keyed by repo + PR) so the fallback isn't re-fetched
    # when the same repo is downloaded by more than one project. Commit text doesn't depend on
    # project_keys, so it's safe to share across projects with different keys. prefetch_commit_messages
    # normally fills this in via a batched request; this single-PR path is the fallback.
    @raw_pr_cache[[@repo, :commits, pr_number]] ||= begin
      args = ['pr', 'view', pr_number.to_s, '--json', 'commits', '--repo', @repo]
      result = run_command(args)
      (result['commits'] || []).flat_map do |commit|
        [commit['messageHeadline'], commit['messageBody']].compact
      end
    end
  end

  def build_issue_key_pattern
    return nil if @project_keys.empty?

    keys_pattern = @project_keys.map { |k| Regexp.escape(k) }.join('|')
    Regexp.new("\\b(?:#{keys_pattern})-\\d+(?![A-Za-z0-9])")
  end

  def monotonic_time
    # In its own method so we can mock it out in tests
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def run_command args
    attempts = 0
    loop do
      attempts += 1
      started = monotonic_time
      stdout, stderr, status = Open3.capture3('gh', *args)
      @file_system.diagnostic "gh #{args.first(2).join(' ')} call took #{format('%.2f', monotonic_time - started)}s"

      # This extra check seems to only matter on Windows. On the mac, auth failures don't pass status.success?
      if stderr.include?('SAML enforcement')
        raise "GitHub CLI is not authorized to access #{@repo}. " \
              'Run: gh auth refresh -h github.com -s read:org'
      end

      unless status.success?
        error_message = "  GitHub CLI command failed for #{@repo} " \
                        "(attempt #{attempts}/#{MAX_RETRIES}): #{stderr.strip}"
        if attempts < MAX_RETRIES && transient_error?(stderr)
          delay = 2**attempts
          @file_system.log error_message
          @file_system.log "  Transient error detected. Retrying in #{delay}s..."
          sleep delay
          next
        end
        @file_system.warning error_message
        raise "GitHub CLI command failed for #{@repo}: #{stderr}"
      end

      return parse_command_result(stdout)
    end
  end

  # stderr is a String (from Open3.capture3), so this include? is String#include? — a substring
  # match ("does the error text contain this phrase?"), not Array membership. Style/ArrayIntersect
  # can't tell the two apart; its `.intersect?(stderr)` rewrite would be an exact-equality check
  # that never matches, silently killing the retry-on-transient-error logic.
  def transient_error? stderr
    TRANSIENT_ERROR_PATTERNS.any? { |pattern| stderr.include?(pattern) } # rubocop:disable Style/ArrayIntersect
  end

  def parse_command_result stdout
    result = JSON.parse(stdout)
    if result.nil? || (result.is_a?(Array) && result.empty?)
      @file_system.warning "No data was found in GitHub for #{@repo}. Is that what you expected?"
    end
    result
  end
end
