# frozen_string_literal: true

class DownloadIssueData
  attr_accessor :key, :found_in_primary_query, :last_modified,
    :up_to_date, :cache_path, :issue
end

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
    intercept_jql = @download_config.project_config.settings['intercept_jql']
    jql = intercept_jql.call jql if intercept_jql

    issue_data_hash = search_for_issues jql: jql, board_id: board.id, path: path
    # puts 'issue_data_hash'
    loop do
      related_issue_keys = Set.new
      issue_data_hash
        .values
        .reject { |data| data.up_to_date }
        .each_slice(100) do |slice|
          puts 'slice'
          bulk_fetch_issues(
            issue_datas: slice, board: board, in_initial_query: true
          )
          slice.each do |data|
            @file_system.save_json(
              json: data.issue.raw, filename: data.cache_path
            )
            # Set the timestamp on the file to match the updated one so that we don't have
            # to parse the file just to find the timestamp
            @file_system.utime time: data.issue.updated, file: data.cache_path

            puts "#{data.issue.key} #{data.issue.summary}"
            slice.each do |data|
              issue = data.issue
              next unless issue

              parent_key = issue.parent_key(project_config: @download_config.project_config)
              related_issue_keys << parent_key if parent_key

              # Sub-tasks
              issue.raw['fields']['subtasks']&.each do |raw_subtask|
                related_issue_keys << raw_subtask['key']
              end
            end
          end
        end

      # Remove all the ones we already downloaded
      related_issue_keys.reject! { |key| issue_data_hash[key] }

      related_issue_keys.each do |key|
        data = DownloadIssueData.new
        data.key = key
        data.found_in_primary_query = false
        data.up_to_date = false
        data.cache_path = File.join(path, "#{key}-#{board.id}.json")
        issue_data_hash[key] = data
      end
      puts 'end of loop'
      break if related_issue_keys.empty?

      log "  Downloading linked issues for board #{board.id}", both: true
    end

    delete_issues_from_cache_that_are_not_in_server(
      issue_data_hash: issue_data_hash, path: path
    )
  end

  def delete_issues_from_cache_that_are_not_in_server issue_data_hash:, path:
    # Walk through all the items in the cache. If they aren't found in issue_data_hash
    # then that means they were deleted in Jira, so we flush them.
    @file_system.foreach path do |file|
      next if file.start_with? '.'
      raise "Unexpected filename in #{path}: #{file}" unless file =~ /^(\w+-\d+)-\d+\.json$/

      next if issue_data_hash[$1]

      file_to_delete = File.join(path, file)
      puts "Deleting #{file_to_delete}"
      # TODO: Actually do the delete
    end
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

  def save_issue issue:
    file = "#{issue.key}-#{issue.board.id}.json"

    @file_system.save_json(json: issue_json, filename: File.join(path, file))

    issue = Issue.new(raw: issue_json, board: board)
    puts "#{issue.key} #{issue.summary}"
  end

  def last_modified filename:
    return nil unless File.exist?(filename)

    File.mtime(filename)
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
end
