# frozen_string_literal: true

class DownloaderForCloud < Downloader
  def download_issues board:
    log "  Downloading primary issues for board #{board.id} from Jira Cloud", both: true
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

    max_results = 5_000 # The maximum allowed by Jira
    next_page_token = nil
    issue_count = 0

    loop do
      relative_url = +''
      relative_url << '/rest/api/3/search/jql'
      relative_url << "?jql=#{escaped_jql}&maxResults=#{max_results}"
      relative_url << "&nextPageToken=#{next_page_token}" if next_page_token
      relative_url << '&expand=changelog&fields=*all'

      json = @jira_gateway.call_url relative_url: relative_url
      next_page_token = json['nextPageToken']

      json['issues'].each do |issue_json|
        issue_json['exporter'] = {
          'in_initial_query' => initial_query
        }
        identify_other_issues_to_be_downloaded raw_issue: issue_json, board: board
        file = "#{issue_json['key']}-#{board.id}.json"

        @file_system.save_json(json: issue_json, filename: File.join(path, file))
        issue_count += 1
      end

      message = "    Downloaded #{issue_count} issues"
      log message, both: true

      break unless next_page_token
    end
  end
end
