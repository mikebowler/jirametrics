# frozen_string_literal: true

class DownloadIssueData
  attr_accessor :key, :found_in_primary_query, :last_modified,
    :up_to_date, :cache_path, :issue
end

class DownloaderForDataCenter < Downloader
  def jira_instance_type
    'Jira DataCenter'
  end

  def search_for_issues jql:, board_id:, path:
    log "  JQL: #{jql}"
    escaped_jql = CGI.escape jql

    hash = {}
    max_results = 100
    start_at = 0
    total = 1
    while start_at < total
      json = @jira_gateway.call_url relative_url: '/rest/api/2/search' \
        "?jql=#{escaped_jql}&maxResults=#{max_results}&startAt=#{start_at}&fields=updated"
      json['issues'].each do |i|
        key = i['key']
        data = DownloadIssueData.new
        data.key = key
        data.last_modified = Time.parse i['fields']['updated']
        data.found_in_primary_query = true
        data.cache_path = File.join(path, "#{key}-#{board_id}.json")
        data.up_to_date = last_modified(filename: data.cache_path) == data.last_modified
        hash[key] = data
      end
      total = json['total'].to_i
      max_results = json['maxResults']

      message = "    Downloaded #{start_at + 1}-#{[start_at + max_results, total].min} of #{total} issues to #{path} "
      log message, both: true

      start_at += json['issues'].size
    end
    hash
  end

  def bulk_fetch_issues issue_datas:, board:, in_initial_query:
    payload = {
      'expand' => [
        'changelog'
      ],
      'fields' => ['*all'],
      'issueIdsOrKeys' => issue_datas.collect(&:key)
    }
    response = @jira_gateway.post_request(
      relative_url: '/rest/api/2/issue/bulkfetch',
      payload: JSON.generate(payload)
    )
    response['issues'].each do |issue_json|
      issue_json['exporter'] = {
        'in_initial_query' => in_initial_query
      }
      issue = Issue.new(raw: issue_json, board: board)
      data = issue_datas.find { |d| d.key == issue.key }
      data.up_to_date = true
      data.last_modified = issue.updated
      data.issue = issue
    end
  end
end
