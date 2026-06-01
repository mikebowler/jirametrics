# frozen_string_literal: true

# Helper module for fetching complete worklog data from Jira
# Handles pagination to retrieve all worklogs, not just the default 20 returned by Jira
module WorklogHelper
  # Merge complete worklogs into issue JSON by pagination
  # For Jira Cloud using bulk fetch API
  def attach_worklogs_to_issues issue_datas:, issue_jsons:
    max_results = 100
    payload = {
      'issueIdsOrKeys' => issue_datas.collect(&:key),
      'maxResults' => max_results
    }

    loop do
      response = @jira_gateway.post_request(
        relative_url: '/rest/api/3/issue/worklog/bulkfetch',
        payload: JSON.generate(payload)
      )

      response['issues'].each do |worklog_data|
        issue_id = worklog_data['issueId']
        json = issue_jsons.find { |j| j['id'] == issue_id }
        next unless json

        unless json['worklog']
          json['worklog'] = {
            'startAt' => 0,
            'maxResults' => max_results,
            'total' => 0,
            'worklogs' => []
          }
        end

        new_worklogs = worklog_data['worklogs'] || []
        json['worklog']['total'] += new_worklogs.size
        json['worklog']['worklogs'] += new_worklogs

        log "      Enhanced #{json['key']} with #{new_worklogs.size} worklogs" if new_worklogs.any?
      end

      next_page_token = response['nextPageToken']
      payload['nextPageToken'] = next_page_token
      break if next_page_token.nil?
    end
  end

  # Fetch complete worklogs for a single issue and update the saved JSON
  # For Jira Data Center using sequential fetch API
  def enhance_issue_with_worklogs issue_key:, issue_path:
    all_worklogs = []
    start_at = 0
    max_results = 100

    loop do
      url = "/rest/api/2/issue/#{CGI.escape(issue_key)}/worklog?startAt=#{start_at}&maxResults=#{max_results}"
      response = @jira_gateway.call_url(relative_url: url)

      worklogs = response['worklogs'] || []
      all_worklogs.concat(worklogs)

      total = response['total'].to_i
      break if start_at + worklogs.size >= total

      start_at += max_results
    end

    # Reload the saved issue and update worklogs
    issue_json = @file_system.load_json(issue_path)
    issue_json['worklog'] = {
      'startAt' => 0,
      'maxResults' => all_worklogs.size,
      'total' => all_worklogs.size,
      'worklogs' => all_worklogs
    }
    @file_system.save_json(json: issue_json, filename: issue_path)

    log "      Enhanced #{issue_key} with #{all_worklogs.size} worklogs" if all_worklogs.any?
  end
end
