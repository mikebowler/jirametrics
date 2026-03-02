# frozen_string_literal: true

require 'open3'
require 'json'

class GithubGateway
  attr_reader :repo

  def initialize repo:, project_keys:, file_system:
    @repo = repo
    @project_keys = project_keys
    @file_system = file_system
    @issue_key_pattern = build_issue_key_pattern
  end

  def fetch_pull_requests since: nil
    # Note: 'commits' is intentionally excluded — including it triggers GitHub's GraphQL node
    # limit (authors sub-connection × PRs × commits exceeds 500,000 nodes). Branch name,
    # title, and body are sufficient for issue key extraction in the vast majority of cases.
    args = %w[pr list --state all --limit 5000
              --json number,title,body,headRefName,createdAt,closedAt,mergedAt,url,state,reviews]
    args += ['--repo', @repo]
    args += ['--search', "updated:>=#{since}"] if since

    @file_system.log "  Downloading pull requests from #{@repo}", also_write_to_stderr: true
    raw_prs = run_command(args)
    raw_prs.filter_map { |pr| build_pr_data(pr) }
  end

  def build_pr_data raw_pr
    issue_keys = extract_issue_keys(raw_pr)
    return nil if issue_keys.empty?

    {
      'number'     => raw_pr['number'],
      'repo'       => @repo,
      'url'        => raw_pr['url'],
      'title'      => raw_pr['title'],
      'branch'     => raw_pr['headRefName'],
      'opened_at'  => raw_pr['createdAt'],
      'closed_at'  => raw_pr['closedAt'],
      'merged_at'  => raw_pr['mergedAt'],
      'state'      => raw_pr['state'],
      'issue_keys' => issue_keys,
      'reviews'    => extract_reviews(raw_pr['reviews'] || [])
    }
  end

  def extract_issue_keys raw_pr
    return [] if @issue_key_pattern.nil?

    sources = [
      raw_pr['headRefName'],
      raw_pr['title'],
      raw_pr['body']
    ]

    sources.compact
           .flat_map { |s| s.scan(@issue_key_pattern) }
           .uniq
  end

  def extract_reviews raw_reviews
    raw_reviews
      .select { |r| %w[APPROVED CHANGES_REQUESTED].include?(r['state']) }
      .map do |r|
        {
          'author'       => r.dig('author', 'login'),
          'submitted_at' => r['submittedAt'],
          'state'        => r['state']
        }
      end
  end

  private

  def build_issue_key_pattern
    return nil if @project_keys.empty?

    keys_pattern = @project_keys.map { |k| Regexp.escape(k) }.join('|')
    Regexp.new("\\b(?:#{keys_pattern})-\\d+\\b")
  end

  def run_command args
    stdout, stderr, status = Open3.capture3('gh', *args)
    raise "GitHub CLI command failed for #{@repo}: #{stderr}" unless status.success?

    JSON.parse(stdout)
  end
end
