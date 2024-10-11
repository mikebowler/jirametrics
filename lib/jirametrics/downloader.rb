# frozen_string_literal: true

require 'cgi'
require 'json'

class Downloader
  CURRENT_METADATA_VERSION = 4

  attr_accessor :metadata
  attr_reader :file_system

  # For testing only
  attr_reader :start_date_in_query, :board_id_to_filter_id

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

    init_gateway
    load_metadata

    if @metadata['no-download']
      log '  Skipping download. Found no-download in meta file', both: true
      return
    end

    # board_ids = @download_config.board_ids

    remove_old_files
    download_statuses
    find_board_ids.each do |id|
      board = download_board_configuration board_id: id
      download_issues board: board
    end

    save_metadata
  end

  def init_gateway
    @jira_gateway.load_jira_config(@download_config.project_config.jira_config)
    @jira_gateway.ignore_ssl_errors = @download_config.project_config.settings['ignore_ssl_errors']
  end

  def log text, both: false
    @file_system.log text, also_write_to_stderr: both
  end

  def find_board_ids
    ids = @download_config.project_config.board_configs.collect(&:id)
    raise 'Board ids must be specified' if ids.empty?

    ids
  end

  def download_issues board:
    log "  Downloading primary issues for board #{board.id}", both: true
    path = "#{@target_path}#{@download_config.project_config.file_prefix}_issues/"
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

      exit_if_call_failed json

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

  def exit_if_call_failed json
    # Sometimes Jira returns the singular form of errorMessage and sometimes the plural. Consistency FTW.
    return unless json['error'] || json['errorMessages'] || json['errorMessage']

    log "Download failed. See #{@file_system.logfile_name} for details.", both: true
    log "  #{JSON.pretty_generate(json)}"
    exit 1
  end

  def download_statuses
    log '  Downloading all statuses', both: true
    json = @jira_gateway.call_url relative_url: '/rest/api/2/status'

    @file_system.save_json(
      json: json,
      filename: "#{@target_path}#{@download_config.project_config.file_prefix}_statuses.json"
    )
  end

  def download_board_configuration board_id:
    log "  Downloading board configuration for board #{board_id}", both: true
    json = @jira_gateway.call_url relative_url: "/rest/agile/1.0/board/#{board_id}/configuration"

    exit_if_call_failed json

    file_prefix = @download_config.project_config.file_prefix
    @file_system.save_json json: json, filename: "#{@target_path}#{file_prefix}_board_#{board_id}_configuration.json"

    # We have a reported bug that blew up on this line. Moved it after the save so we can
    # actually look at the returned json.
    @board_id_to_filter_id[board_id] = json['filter']['id'].to_i

    download_sprints board_id: board_id if json['type'] == 'scrum'
    Board.new raw: json
  end

  def download_sprints board_id:
    log "  Downloading sprints for board #{board_id}", both: true
    file_prefix = @download_config.project_config.file_prefix
    max_results = 100
    start_at = 0
    is_last = false

    while is_last == false
      json = @jira_gateway.call_url relative_url: "/rest/agile/1.0/board/#{board_id}/sprint?" \
        "maxResults=#{max_results}&startAt=#{start_at}"
      exit_if_call_failed json

      @file_system.save_json(
        json: json,
        filename: "#{@target_path}#{file_prefix}_board_#{board_id}_sprints_#{start_at}.json"
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
    "#{@target_path}#{@download_config.project_config.file_prefix}_meta.json"
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
    file_prefix = @download_config.project_config.file_prefix
    Dir.foreach @target_path do |file|
      next unless file.match?(/^#{file_prefix}_\d+\.json$/)

      File.unlink "#{@target_path}#{file}"
    end

    return if @cached_data_format_is_current

    # Also throw away all the previously downloaded issues.
    path = File.join @target_path, "#{file_prefix}_issues"
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

      # For an incremental download, we want to query from the end of the previous one, not from the
      # beginning of the full range.
      @start_date_in_query = metadata['date_end'] || @download_date_range.begin
      log "    Incremental download only. Pulling from #{@start_date_in_query}", both: true if metadata['date_end']

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
end
