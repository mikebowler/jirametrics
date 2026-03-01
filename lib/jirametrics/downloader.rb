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
  CURRENT_METADATA_VERSION = 5

  attr_accessor :metadata
  attr_reader :file_system

  # For testing only
  attr_reader :start_date_in_query, :board_id_to_filter_id

  def self.create download_config:, file_system:, jira_gateway:
    is_cloud = jira_gateway.settings['jira_cloud'] || jira_gateway.cloud?
    (is_cloud ? DownloaderForCloud : DownloaderForDataCenter).new(
      download_config: download_config,
      file_system: file_system,
      jira_gateway: jira_gateway
    )
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
    return unless @jira_gateway.cloud?

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

      # If rolling_date_count has changed, we may be missing data outside the previous range,
      # so force a full re-download.
      if @metadata['rolling_date_count'] != @download_config.rolling_date_count
        log '  rolling_date_count has changed. Forcing a full download.', both: true
        @cached_data_format_is_current = false
        @metadata = {}
      end
    end

    # Even if this is the old format, we want to obey this one tag
    @metadata['no-download'] = hash['no-download'] if hash['no-download']
  end

  def timezone_offset
    @download_config.project_config.exporter.timezone_offset
  end

  def today_in_project_timezone
    Time.now.getlocal(timezone_offset).to_date
  end

  def save_metadata
    @metadata['version'] = CURRENT_METADATA_VERSION
    @metadata['rolling_date_count'] = @download_config.rolling_date_count
    @metadata['date_start_from_last_query'] = @start_date_in_query if @start_date_in_query

    if @download_date_range.nil?
      log "Making up a date range in meta since one wasn't specified. You'll want to change that.", both: true
      today = today_in_project_timezone
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

  def make_jql filter_id:, today: nil
    today ||= today_in_project_timezone
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
end
