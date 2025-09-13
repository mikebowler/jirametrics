# frozen_string_literal: true

class DownloaderForDataCenter < Downloader
  def download_issues board:
    log "  Downloading primary issues for board #{board.id} from Jira DataCenter", both: true
    path = File.join(@target_path, "#{file_prefix}_issues/")
    unless Dir.exist?(path)
      log "  Creating path #{path}"
      Dir.mkdir(path)
    end

    filter_id = @board_id_to_filter_id[board.id]
    jql = make_jql(filter_id: filter_id)
    jira_search_by_jql(jql: jql, initial_query: true, board: board, path: path)

    log "  Downloading linked issues for board #{board.id}", both: true
    loop do
      @issue_keys_pending_download.reject! { |key| @issue_keys_downloaded_in_current_run.include? key }
      break if @issue_keys_pending_download.empty?

      keys_to_request = @issue_keys_pending_download[0..99]
      @issue_keys_pending_download.reject! { |key| keys_to_request.include? key }
      jql = "key in (#{keys_to_request.join(', ')})"
      jira_search_by_jql(jql: jql, initial_query: false, board: board, path: path)
    end
  end

  def jira_search_by_jql jql:, initial_query:, board:, path:
    intercept_jql = @download_config.project_config.settings['intercept_jql']
    jql = intercept_jql.call jql if intercept_jql

    log "  JQL: #{jql}"
    escaped_jql = CGI.escape jql

    max_results = 100
    start_at = 0
    total = 1
    while start_at < total
      json = @jira_gateway.call_url relative_url: '/rest/api/2/search' \
        "?jql=#{escaped_jql}&maxResults=#{max_results}&startAt=#{start_at}&expand=changelog&fields=*all"

      json['issues'].each do |issue_json|
        issue_json['exporter'] = {
          'in_initial_query' => initial_query
        }
        identify_other_issues_to_be_downloaded raw_issue: issue_json, board: board
        file = "#{issue_json['key']}-#{board.id}.json"

        @file_system.save_json(json: issue_json, filename: File.join(path, file))
      end

      total = json['total'].to_i
      max_results = json['maxResults']

      message = "    Downloaded #{start_at + 1}-#{[start_at + max_results, total].min} of #{total} issues to #{path} "
      log message, both: true

      start_at += json['issues'].size
    end
  end
end
