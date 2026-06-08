# frozen_string_literal: true

module WorklogHelper
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
