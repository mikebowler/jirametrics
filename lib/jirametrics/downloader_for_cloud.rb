# frozen_string_literal: true

class DownloaderForCloud < Downloader
  def jira_instance_type
    'Jira Cloud'
  end

  def run
    super
    download_fix_versions
  end

  def download_board_configuration board_id:
    board = super
    location = board.raw['location']
    @project_key ||= location['key'] if location&.[]('type') == 'project'
    board
  end

  def download_fix_versions
    return unless @project_key

    log "  Downloading fix versions for project #{@project_key}", both: true
    max_results = 50
    start_at = 0
    all_versions = []

    loop do
      json = @jira_gateway.call_url(
        relative_url: "/rest/api/3/project/#{@project_key}/version?" \
          "startAt=#{start_at}&maxResults=#{max_results}"
      )

      values = json['values'] || []
      all_versions.concat(values)
      break if json['isLast'] || values.empty?

      start_at += values.size
    end

    @file_system.save_json(
      json: all_versions,
      filename: File.join(@target_path, "#{file_prefix}_fix_versions.json")
    )
  end

  def search_for_issues jql:, board_id:, path:
    log "  JQL: #{jql}"
    escaped_jql = CGI.escape jql

    hash = {}
    max_results = 5_000 # The maximum allowed by Jira
    next_page_token = nil
    issue_count = 0

    start_progress
    loop do
      relative_url = +''
      relative_url << '/rest/api/3/search/jql'
      relative_url << "?jql=#{escaped_jql}&maxResults=#{max_results}"
      relative_url << "&nextPageToken=#{next_page_token}" if next_page_token
      relative_url << '&fields=updated'

      json = @jira_gateway.call_url relative_url: relative_url
      next_page_token = json['nextPageToken']

      json['issues'].each do |i|
        key = i['key']
        data = DownloadIssueData.new key: key
        data.key = key
        data.last_modified = Time.parse i['fields']['updated']
        data.found_in_primary_query = true
        data.cache_path = File.join(path, "#{key}-#{board_id}.json")
        data.up_to_date = last_modified(filename: data.cache_path) == data.last_modified
        hash[key] = data
        issue_count += 1
      end

      progress_dot "    Found #{issue_count} issues"

      break unless next_page_token
    end
    end_progress

    hash
  end

  def bulk_fetch_issues issue_datas:, board:, in_initial_query:
    # We used to use the expand option to pull in the changelog directly. Unfortunately
    # that only returns the "recent" changes, not all of them. So now we get the issue
    # without changes and then make a second call for that changes. Then we insert it
    # into the raw issue as if it had been there all along.
    log "  Downloading #{issue_datas.size} issues"
    payload = {
      'fields' => ['*all'],
      'issueIdsOrKeys' => issue_datas.collect(&:key)
    }
    response = @jira_gateway.post_request(
      relative_url: '/rest/api/3/issue/bulkfetch',
      payload: JSON.generate(payload)
    )

    attach_changelog_to_issues issue_datas: issue_datas, issue_jsons: response['issues']
    attach_worklogs_to_issues issue_datas: issue_datas, issue_jsons: response['issues']

    response['issues'].each do |issue_json|
      issue_json['exporter'] = {
        'in_initial_query' => in_initial_query
      }
      issue = Issue.new(raw: issue_json, board: board)
      data = issue_datas.find { |d| d.key == issue.key }
      unless data
        log "  Skipping #{issue.key}: returned by Jira but key not in request (issue may have been moved)"
        next
      end
      data.up_to_date = true
      data.last_modified = issue.updated
      data.issue = issue
    end

    # Mark any unmatched requests as up_to_date to prevent infinite re-fetching.
    # This happens when Jira returns a different key (moved issue) leaving the original unmatched.
    issue_datas.each do |data|
      next if data.up_to_date

      log "  Skipping #{data.key}: not returned by Jira (issue may have been deleted or moved)"
      data.up_to_date = true
    end

    issue_datas
  end

  def attach_worklogs_to_issues issue_datas:, issue_jsons:, max_results: 100 # rubocop:disable Lint/UnusedMethodArgument
    issue_jsons.each do |issue_json|
      worklog = issue_json['fields']['worklog']
      next unless worklog

      total = worklog['total'].to_i
      all_worklogs = worklog['worklogs'] || []
      next if all_worklogs.size >= total

      key = issue_json['key']
      start_at = all_worklogs.size

      loop do
        response = @jira_gateway.call_url(
          relative_url: "/rest/api/3/issue/#{CGI.escape(key)}/worklog?startAt=#{start_at}&maxResults=#{max_results}"
        )

        worklogs = response['worklogs'] || []
        all_worklogs.concat(worklogs)

        total = response['total'].to_i
        log "        #{key} worklogs: page startAt=#{start_at}, " \
            "received=#{worklogs.size}, fetched=#{all_worklogs.size}/#{total}"
        break if all_worklogs.size >= total
        # Guard against Jira reporting a higher total than it will actually return — seen when
        # worklogs are deleted or access-restricted after the initial fetch. Without this,
        # start_at never advances and we loop forever requesting the same empty page.
        break if worklogs.empty?

        start_at += worklogs.size
      end

      issue_json['fields']['worklog'] = {
        'startAt' => 0,
        'maxResults' => all_worklogs.size,
        'total' => all_worklogs.size,
        'worklogs' => all_worklogs
      }

      log "      Enhanced #{key} with #{all_worklogs.size} worklogs"
    end
  end

  def attach_changelog_to_issues issue_datas:, issue_jsons:
    max_results = 10_000 # The max jira accepts is 10K
    payload = {
      'issueIdsOrKeys' => issue_datas.collect(&:key),
      'maxResults' => max_results
    }
    loop do
      response = @jira_gateway.post_request(
        relative_url: '/rest/api/3/changelog/bulkfetch',
        payload: JSON.generate(payload)
      )

      response['issueChangeLogs'].each do |issue_change_log|
        issue_id = issue_change_log['issueId']
        json = issue_jsons.find { |json| json['id'] == issue_id }

        unless json['changelog']
          # If this is our first time in, there won't be a changelog section
          json['changelog'] = {
            'startAt' => 0,
            'maxResults' => max_results,
            'total' => 0,
            'histories' => []
          }
        end

        new_changes = issue_change_log['changeHistories']
        json['changelog']['total'] += new_changes.size
        json['changelog']['histories'] += new_changes
      end

      next_page_token = response['nextPageToken']
      payload['nextPageToken'] = next_page_token
      break if next_page_token.nil?
    end
  end

  def download_issues board:
    log "  Downloading primary issues for board #{board.id} from #{jira_instance_type}", both: true
    path = File.join(@target_path, "#{file_prefix}_issues/")
    unless @file_system.dir_exist?(path)
      log "  Creating path #{path}"
      @file_system.mkdir(path)
    end

    filter_id = @board_id_to_filter_id[board.id]
    jql = make_jql(filter_id: filter_id)
    intercept_jql = @download_config.project_config.settings['intercept_jql']
    jql = intercept_jql.call jql if intercept_jql

    issue_data_hash = search_for_issues jql: jql, board_id: board.id, path: path

    checked_for_related = Set.new
    in_related_phase = false

    loop do
      related_issue_keys = Set.new
      stale = issue_data_hash.values.reject { |data| data.up_to_date }
      if in_related_phase
        log "  [diag] Download loop: #{issue_data_hash.size} total known, " \
            "#{stale.size} stale, #{checked_for_related.size} link-scanned"
      end
      unless stale.empty?
        log_start '  Downloading more issues ' unless in_related_phase
        stale.each_slice(100) do |slice|
          slice = bulk_fetch_issues(issue_datas: slice, board: board, in_initial_query: !in_related_phase)
          progress_dot
          slice.each do |data|
            next unless data.issue

            @file_system.save_json(
              json: data.issue.raw, filename: data.cache_path
            )
            # Set the timestamp on the file to match the updated one so that we don't have
            # to parse the file just to find the timestamp
            @file_system.utime time: data.issue.updated, file: data.cache_path

            collect_or_log_related(
              issue: data.issue, found_in_primary_query: data.found_in_primary_query,
              related_issue_keys: related_issue_keys, issue_data_hash: issue_data_hash
            )
            checked_for_related << data.key
          end
        end
        end_progress unless in_related_phase
      end

      scan_cached_issues_for_related(
        issue_data_hash: issue_data_hash, board: board,
        checked_for_related: checked_for_related, related_issue_keys: related_issue_keys
      )

      # Remove all the ones we already have
      related_issue_keys.reject! { |key| issue_data_hash[key] }

      related_issue_keys.each do |key|
        data = DownloadIssueData.new key: key
        data.found_in_primary_query = false
        data.up_to_date = false
        data.cache_path = File.join(path, "#{key}-#{board.id}.json")
        issue_data_hash[key] = data
      end
      break if related_issue_keys.empty?

      next if in_related_phase

      in_related_phase = true
      log "  Identifying related issues (parents, subtasks, links) for board #{board.id}", both: true
      log_start '  Downloading more issues '
    end

    end_progress if in_related_phase

    delete_issues_from_cache_that_are_not_in_server(
      issue_data_hash: issue_data_hash, path: path
    )
  end

  def delete_issues_from_cache_that_are_not_in_server issue_data_hash:, path:
    # The gotcha with deleted issues is that they just stop being returned in queries
    # and we have no way to know that they should be removed from our local cache.
    # With the new approach, we ask for every issue that Jira knows about (within
    # the parameters of the query) and then delete anything that's in our local cache
    # but wasn't returned.
    @file_system.foreach path do |file|
      next if file.start_with? '.'
      unless /^(?<key>\w+-\d+)-\d+\.json$/ =~ file
        raise "Unexpected filename in #{path}: #{file}"
      end
      next if issue_data_hash[key] # Still in Jira

      file_to_delete = File.join(path, file)
      log "  Removing #{file_to_delete} from local cache"
      file_system.unlink file_to_delete
    end
  end

  # Scan up-to-date cached primary issues we haven't checked yet — they may reference related
  # issues that are not in the primary query result. We only follow links one hop out from the
  # primary issues, so related (non-primary) cached issues are not followed (just logged).
  def scan_cached_issues_for_related issue_data_hash:, board:, checked_for_related:, related_issue_keys:
    issue_data_hash.each_value do |data|
      next if checked_for_related.include?(data.key)
      next unless @file_system.file_exist?(data.cache_path)

      checked_for_related << data.key
      issue = Issue.new(raw: @file_system.load_json(data.cache_path), board: board)
      collect_or_log_related(
        issue: issue, found_in_primary_query: data.found_in_primary_query,
        related_issue_keys: related_issue_keys, issue_data_hash: issue_data_hash
      )
    end
  end

  # Follow links one hop out from primary issues; for related (non-primary) issues, log the
  # onward links we are deliberately not following rather than recursing into them.
  def collect_or_log_related issue:, found_in_primary_query:, related_issue_keys:, issue_data_hash:
    if found_in_primary_query
      collect_related_issue_keys issue: issue, related_issue_keys: related_issue_keys
    else
      log_unfollowed_related_keys issue: issue, issue_data_hash: issue_data_hash
    end
  end

  def collect_related_issue_keys issue:, related_issue_keys:
    related_issue_keys.merge related_keys_for(issue)
  end

  # The parents, subtasks, and (non-cloner) linked issues that this issue references.
  def related_keys_for issue
    keys = Set.new

    parent_key = issue.parent_key(project_config: @download_config.project_config)
    keys << parent_key if parent_key

    issue.raw['fields']['subtasks']&.each do |raw_subtask|
      keys << raw_subtask['key']
    end

    issue.raw['fields']['issuelinks']&.each do |link|
      next if link['type']['name'] == 'Cloners'

      linked = link['inwardIssue'] || link['outwardIssue']
      keys << linked['key'] if linked
    end

    keys
  end

  # We only follow links one hop out from the primary (board) issues. If a related issue
  # itself references further issues we haven't already downloaded, we deliberately don't
  # follow them — but log it so we can diagnose later if an export fails because a
  # second-hop issue was missing. See GitHub #72.
  def log_unfollowed_related_keys issue:, issue_data_hash:
    onward = related_keys_for(issue).reject { |key| issue_data_hash[key] }
    return if onward.empty?

    log "  [diag] One-hop limit: not following #{onward.size} onward link(s) from related " \
        "issue #{issue.key}: #{onward.to_a.sort.join(', ')}"
  end

  def last_modified filename:
    File.mtime(filename) if File.exist?(filename)
  end
end
