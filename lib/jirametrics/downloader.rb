# frozen_string_literal: true

require 'cgi'
require 'json'

class DownloadIssueData
  attr_accessor :key, :found_in_primary_query, :last_modified,
    :up_to_date, :cache_path, :issue

  def initialize(
    key:,
    found_in_primary_query: true,
    last_modified: nil,
    up_to_date: true,
    cache_path: nil,
    issue: nil
  )
    @key = key
    @found_in_primary_query = found_in_primary_query
    @last_modified = last_modified
    @up_to_date = up_to_date
    @cache_path = cache_path
    @issue = issue
  end
end

class Downloader
  CURRENT_METADATA_VERSION = 4

  attr_accessor :metadata
  attr_reader :file_system

  # For testing only
  attr_reader :start_date_in_query, :board_id_to_filter_id

  def self.create download_config:, file_system:, jira_gateway:
    if jira_gateway.cloud?
      DownloaderForCloud.new(
        download_config: download_config,
        file_system: file_system,
        jira_gateway: jira_gateway
      )
    else
      DownloaderForDataCenter.new(
        download_config: download_config,
        file_system: file_system,
        jira_gateway: jira_gateway
      )
    end
  end

  def initialize download_config:, file_system:, jira_gateway:
    @metadata = {}
    @download_config = download_config
    @target_path = @download_config.project_config.target_path
    @file_system = file_system
    @jira_gateway = jira_gateway
    @board_id_to_filter_id = {}

    @issue_keys_downloaded_in_current_run = []
    @issue_keys_pending_download = []
  end

  def run
    log '', both: true
    log @download_config.project_config.name, both: true

    load_metadata

    if @metadata['no-download']
      log '  Skipping download. Found no-download in meta file', both: true
      return
    end

    # board_ids = @download_config.board_ids

    remove_old_files
    update_status_history_file
    download_statuses
    find_board_ids.each do |id|
      board = download_board_configuration board_id: id
      download_issues board: board
    end
    download_users

    save_metadata
  end

  def log text, both: false
    @file_system.log text, also_write_to_stderr: both
  end

  def find_board_ids
    ids = @download_config.project_config.board_configs.collect(&:id)
    raise 'Board ids must be specified' if ids.empty?

    ids
  end

  def identify_other_issues_to_be_downloaded raw_issue:, board:
    issue = Issue.new raw: raw_issue, board: board
    @issue_keys_downloaded_in_current_run << issue.key

    # Parent
    parent_key = issue.parent_key(project_config: @download_config.project_config)
    @issue_keys_pending_download << parent_key if parent_key

    # Sub-tasks
    issue.raw['fields']['subtasks']&.each do |raw_subtask|
      @issue_keys_pending_download << raw_subtask['key']
    end
  end

  def download_statuses
    log '  Downloading all statuses', both: true
    json = @jira_gateway.call_url relative_url: '/rest/api/2/status'

    @file_system.save_json(
      json: json,
      filename: File.join(@target_path, "#{file_prefix}_statuses.json")
    )
  end

  def download_users
    log '  Downloading all users', both: true
    json = @jira_gateway.call_url relative_url: '/rest/api/2/users'

    @file_system.save_json(
      json: json,
      filename: File.join(@target_path, "#{file_prefix}_users.json")
    )
  end

  def update_status_history_file
    status_filename = File.join(@target_path, "#{file_prefix}_statuses.json")
    return unless file_system.file_exist? status_filename

    status_json = file_system.load_json(status_filename)

    history_filename = File.join(@target_path, "#{file_prefix}_status_history.json")
    history_json = file_system.load_json(history_filename) if file_system.file_exist? history_filename

    if history_json
      file_system.log '  Updating status history file', also_write_to_stderr: true
    else
      file_system.log '  Creating status history file', also_write_to_stderr: true
      history_json = []
    end

    status_json.each do |status_item|
      id = status_item['id']
      history_item = history_json.find { |s| s['id'] == id }
      history_json.delete(history_item) if history_item
      history_json << status_item
    end

    file_system.save_json(filename: history_filename, json: history_json)
  end

  def download_board_configuration board_id:
    log "  Downloading board configuration for board #{board_id}", both: true
    json = @jira_gateway.call_url relative_url: "/rest/agile/1.0/board/#{board_id}/configuration"

    @file_system.save_json(
      json: json,
      filename: File.join(@target_path, "#{file_prefix}_board_#{board_id}_configuration.json")
    )

    # We have a reported bug that blew up on this line. Moved it after the save so we can
    # actually look at the returned json.
    @board_id_to_filter_id[board_id] = json['filter']['id'].to_i

    download_sprints board_id: board_id if json['type'] == 'scrum'
    # TODO: Should be passing actual statuses, not empty list
    Board.new raw: json, possible_statuses: StatusCollection.new
  end

  def download_sprints board_id:
    log "  Downloading sprints for board #{board_id}", both: true
    max_results = 100
    start_at = 0
    is_last = false

    while is_last == false
      json = @jira_gateway.call_url relative_url: "/rest/agile/1.0/board/#{board_id}/sprint?" \
        "maxResults=#{max_results}&startAt=#{start_at}"

      @file_system.save_json(
        json: json,
        filename: File.join(@target_path, "#{file_prefix}_board_#{board_id}_sprints_#{start_at}.json")
      )
      is_last = json['isLast']
      max_results = json['maxResults']
      if json['values']
        start_at += json['values'].size
      else
        log "  No sprints found for board #{board_id}"
      end
    end
  end

  def metadata_pathname
    File.join(@target_path, "#{file_prefix}_meta.json")
  end

  def load_metadata
    # If we've never done a download before then this file won't be there. That's ok.
    hash = file_system.load_json(metadata_pathname, fail_on_error: false)
    return if hash.nil?

    # Only use the saved metadata if the version number is the same one that we're currently using.
    # If the cached data is in an older format then we're going to throw most of it away.
    @cached_data_format_is_current = (hash['version'] || 0) == CURRENT_METADATA_VERSION
    if @cached_data_format_is_current
      hash.each do |key, value|
        value = Date.parse(value) if value.is_a?(String) && value =~ /^\d{4}-\d{2}-\d{2}$/
        @metadata[key] = value
      end
    end

    # Even if this is the old format, we want to obey this one tag
    @metadata['no-download'] = hash['no-download'] if hash['no-download']
  end

  def save_metadata
    @metadata['version'] = CURRENT_METADATA_VERSION
    @metadata['date_start_from_last_query'] = @start_date_in_query if @start_date_in_query

    if @download_date_range.nil?
      log "Making up a date range in meta since one wasn't specified. You'll want to change that.", both: true
      today = Date.today
      @download_date_range = (today - 7)..today
    end

    @metadata['earliest_date_start'] = @download_date_range.begin if @metadata['earliest_date_start'].nil?

    @metadata['date_start'] = @download_date_range.begin
    @metadata['date_end'] = @download_date_range.end

    @metadata['jira_url'] = @jira_url

    @file_system.save_json json: @metadata, filename: metadata_pathname
  end

  def remove_old_files
    Dir.foreach @target_path do |file|
      next unless file.match?(/^#{file_prefix}_\d+\.json$/)
      next if file == "#{file_prefix}_status_history.json"

      File.unlink File.join(@target_path, file)
    end

    return if @cached_data_format_is_current

    # Also throw away all the previously downloaded issues.
    path = File.join(@target_path, "#{file_prefix}_issues")
    return unless File.exist? path

    Dir.foreach path do |file|
      next unless file.match?(/\.json$/)

      File.unlink File.join(path, file)
    end
  end

  def make_jql filter_id:, today: Date.today
    segments = []
    segments << "filter=#{filter_id}"

    start_date = @download_config.start_date today: today

    if start_date
      @download_date_range = start_date..today.to_date
      @start_date_in_query = @download_date_range.begin

      # Catch-all to pick up anything that's been around since before the range started but hasn't
      # had an update during the range.
      catch_all = '((status changed OR Sprint is not EMPTY) AND statusCategory != Done)'

      # Pick up any issues that had a status change in the range
      start_date_text = @start_date_in_query.strftime '%Y-%m-%d'
      # find_in_range = %((status changed DURING ("#{start_date_text} 00:00","#{end_date_text} 23:59")))
      find_in_range = %(updated >= "#{start_date_text} 00:00")

      segments << "(#{find_in_range} OR #{catch_all})"
    end

    segments.join ' AND '
  end

  def file_prefix
    @download_config.project_config.get_file_prefix
  end

  def download_issues board:
    log "  Downloading primary issues for board #{board.id} from #{jira_instance_type}", both: true
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

    loop do
      related_issue_keys = Set.new
      issue_data_hash
        .values
        .reject { |data| data.up_to_date }
        .each_slice(100) do |slice|
          slice = bulk_fetch_issues(
            issue_datas: slice, board: board, in_initial_query: true
          )
          slice.each do |data|
            @file_system.save_json(
              json: data.issue.raw, filename: data.cache_path
            )
            # Set the timestamp on the file to match the updated one so that we don't have
            # to parse the file just to find the timestamp
            @file_system.utime time: data.issue.updated, file: data.cache_path

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
      break if related_issue_keys.empty?

      log "  Downloading linked issues for board #{board.id}", both: true
    end

    delete_issues_from_cache_that_are_not_in_server(
      issue_data_hash: issue_data_hash, path: path
    )
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
      relative_url: issue_bulk_fetch_api,
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

  def delete_issues_from_cache_that_are_not_in_server issue_data_hash:, path:
    # The gotcha with deleted issues is that they just stop being returned in queries
    # and we have no way to know that they should be removed from our local cache.
    # With the new approach, we ask for every issue that Jira knows about (within
    # the parameters of the query) and then delete anything that's in our local cache
    # but wasn't returned.
    @file_system.foreach path do |file|
      next if file.start_with? '.'
      raise "Unexpected filename in #{path}: #{file}" unless file =~ /^(\w+-\d+)-\d+\.json$/

      key = $1
      next if issue_data_hash[key] # Still in Jira

      file_to_delete = File.join(path, file)
      log "  Issue #{key} appears to have been deleted from Jira. Removing local copy", both: true
      file_system.unlink file_to_delete
    end
  end

  def last_modified filename:
    File.mtime(filename) if File.exist?(filename)
  end
end
