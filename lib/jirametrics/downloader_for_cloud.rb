# frozen_string_literal: true

class DownloaderForCloud < Downloader
  def jira_instance_type
    'Jira Cloud'
  end

  def search_for_issues jql:, board_id:, path:
    log "  JQL: #{jql}"
    escaped_jql = CGI.escape jql

    hash = {}
    max_results = 5_000 # The maximum allowed by Jira
    next_page_token = nil
    issue_count = 0

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

      message = "    Found #{issue_count} issues"
      log message, both: true

      break unless next_page_token
    end
    hash
  end

  def bulk_fetch_issues issue_datas:, board:, in_initial_query:
    log "  Downloading #{issue_datas.size} issues", both: true
    payload = {
      'expand' => [
        'changelog'
      ],
      'fields' => ['*all'],
      'issueIdsOrKeys' => issue_datas.collect(&:key)
    }
    response = @jira_gateway.post_request(
      relative_url: '/rest/api/3/issue/bulkfetch',
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
    issue_datas
  end
end
