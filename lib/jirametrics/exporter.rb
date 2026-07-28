# frozen_string_literal: true

require 'fileutils'

class Exporter
  attr_reader :project_configs
  attr_accessor :file_system

  def self.logfile_name
    @logfile_name ||= 'jirametrics.log'
  end

  # The MCP server sets this to a separate file so starting the server doesn't clobber the
  # export/debug log (jirametrics.log) that someone may be mid-debug on.
  class << self
    attr_writer :logfile_name
  end

  def self.configure &block
    # No block form: FileSystem holds this descriptor open for the whole run and writes to it as we
    # go, so it must outlive this method.
    logfile = File.open(logfile_name, 'w') # rubocop:disable Style/FileOpen
  rescue Errno::EACCES
    # FileSystem can't be used here - it hasn't been created yet (it depends on this logfile).
    warn "Error: Cannot write to #{File.expand_path(logfile_name)}. " \
      'Please ensure the current directory is writable.'
    exit 1
  else
    file_system = FileSystem.new
    file_system.logfile = logfile
    file_system.logfile_name = logfile_name

    exporter = Exporter.new file_system: file_system

    exporter.instance_eval(&block)
    @@instance = exporter
  end

  def self.instance = @@instance

  def initialize file_system: FileSystem.new
    @project_configs = []
    @target_path = '.'
    @holiday_dates = []
    @downloading = false
    @file_system = file_system

    timezone_offset '+00:00'
  end

  def export name_filter:
    each_project_config(name_filter: name_filter) do |project|
      project.evaluate_next_level
      project.run
    end
  end

  def download name_filter:
    @downloading = true
    github_pr_cache = {}
    each_project_config(name_filter: name_filter) do |project|
      project.evaluate_next_level
      next if project.aggregated_project?

      unless project.download_config
        raise "Project #{project.name.inspect} is missing a download section in the config. " \
          'That is required in order to download'
      end

      project.download_config.run
      gateway = JiraGateway.new(
        file_system: file_system, jira_config: project.jira_config, settings: project.settings
      )
      downloader = Downloader.create(
        download_config: project.download_config,
        file_system: file_system,
        jira_gateway: gateway,
        github_pr_cache: github_pr_cache
      )
      downloader.run
    end
    puts "Full output from downloader in #{file_system.logfile_name}"
  end

  def verify_jira_connections name_filter:
    results = []
    begin
      # Probe under log_only so the gateway's raw curl chatter (and its error dumps) stay in the
      # logfile rather than cluttering the console; we surface a clean summary line below.
      file_system.log_only = true
      jira_connections_to_verify(name_filter: name_filter).each do |config, settings|
        gateway = JiraGateway.new(file_system: file_system, jira_config: config, settings: settings)
        results << gateway.verify_connection
      end
    ensure
      file_system.log_only = false
    end

    if results.empty?
      file_system.error 'No Jira connection found in the configuration to verify'
      return results
    end
    results.each { |result| file_system.log result.message, also_write_to_stderr: true }
    results
  end

  # The [jira_config, settings] pairs to verify, deduplicated by URL. We do NOT evaluate_next_level:
  # running a project block (e.g. standard_project) forces an issue-data load that doesn't exist
  # before the first download, and verify must work pre-download. When no project supplied a
  # connection we fall back to the top-level jira_config, so verify can run as a first setup step on
  # just the credentials file. (The fallback has no per-project settings, so a config-block-only
  # setting like ignore_ssl_errors isn't applied. That only affects self-signed
  # Data Center instances.)
  def jira_connections_to_verify name_filter:
    connections = []
    seen_urls = []
    each_project_config(name_filter: name_filter) do |project|
      url = project.jira_config && project.jira_config['url']
      next if url.nil? || seen_urls.include?(url)

      seen_urls << url
      connections << [project.jira_config, project.settings]
    end
    connections << [jira_config, {}] if connections.empty? && jira_config
    connections
  end

  def boards board_id:, name_filter: nil
    gateway = JiraGateway.new(file_system: file_system, jira_config: jira_config, settings: {})
    # Keep the gateway's raw curl chatter in the logfile; list_boards/describe_board switch this off
    # right before they print their own clean output, and the rescue turns a failed Jira call into a
    # one-line message with next steps instead of a stack trace.
    file_system.log_only = true
    if board_id.nil?
      list_boards gateway, name_filter
    else
      describe_board gateway, board_id
    end
    true
  rescue StandardError
    file_system.log_only = false
    file_system.error boards_error_message(board_id)
    false
  ensure
    file_system.log_only = false
  end

  def boards_error_message board_id
    if board_id
      "Couldn't read board #{board_id} from Jira. Check the id (run `jirametrics boards` to list them) " \
        "and your credentials (`jirametrics verify`). Details in #{file_system.logfile_name}."
    else
      "Couldn't list boards from Jira. Check your credentials with `jirametrics verify`. " \
        "Details in #{file_system.logfile_name}."
    end
  end

  def list_boards gateway, name_filter
    boards = fetch_all_boards gateway
    boards.select! { |board| File.fnmatch(name_filter, board['name'].to_s, File::FNM_CASEFOLD) } if name_filter
    boards.sort_by! { |board| board['name'].to_s.strip.downcase }
    file_system.log_only = false # gateway calls done; turn logging back on to print results

    if boards.empty?
      file_system.log(
        name_filter ? "No boards match #{name_filter.inspect}." : 'No boards found for this Jira connection.',
        also_write_to_stderr: true
      )
      return
    end

    lines = ['Boards you can access:', '']
    boards.each { |board| lines << "  #{board['id']}: #{board['name'].inspect} (#{board['type']})" }
    lines << ''
    lines << "Run `jirametrics boards <id>` to see a board's columns and choose cycletime points."
    file_system.log lines.join("\n"), also_write_to_stderr: true
  end

  def fetch_all_boards gateway
    boards = []
    start_at = 0
    loop do
      json = gateway.call_url relative_url: "/rest/agile/1.0/board?startAt=#{start_at}&maxResults=50"
      values = json['values'] || []
      boards.concat values
      break if json['isLast'] || values.empty?

      start_at += values.length
    end
    boards
  end

  def describe_board gateway, board_id
    statuses = StatusCollection.new
    gateway.call_url(relative_url: '/rest/api/2/status').each do |snippet|
      statuses << Status.from_raw(snippet)
    end
    raw = gateway.call_url relative_url: "/rest/agile/1.0/board/#{board_id}/configuration"
    features = board_features(gateway, board_id, raw)
    file_system.log_only = false # gateway calls done; turn logging back on to print results
    board = Board.new raw: raw, possible_statuses: statuses, features: features
    file_system.log format_board(board, board_id), also_write_to_stderr: true
  end

  # Only a team-managed ("simple") board needs the features lookup to tell sprints from kanban; for
  # classic scrum/kanban the board type alone settles it, so we skip the extra request.
  def board_features gateway, board_id, raw
    return [] unless raw['type'] == 'simple'

    BoardFeature.from_raw gateway.call_url(relative_url: "/rest/agile/1.0/board/#{board_id}/features")
  end

  def format_board board, board_id
    lines = ["Board #{board_id}: #{board.name.inspect} (#{board_kind_label board})", '']

    backlog = board.backlog_statuses
    unless backlog.empty?
      lines << 'Not shown on the board (treated as not started):'
      backlog.each { |status| lines << "  - #{format_status status}" }
      lines << ''
    end

    lines << 'Columns, left to right, with the statuses in each (shown as "name":id with its category):'
    lines << ''
    board.visible_columns.each do |column|
      lines << "  #{column.name}"
      column.status_ids.each do |id|
        status = board.possible_statuses.find_by_id id
        lines << "    - #{status ? format_status(status) : "unknown status id #{id}"}"
      end
    end

    lines << ''
    lines << 'To set cycle time, choose the column where work is "started" and where it is "finished":'
    lines << "  start_at first_time_in_or_right_of_column '<started column>'"
    lines << "  stop_at  first_time_in_or_right_of_column '<finished column>'"
    if board.scrum?
      lines << ''
      lines << 'This board uses sprints. If no column cleanly marks when work starts, you can start the'
      lines << 'clock when an item is first added to a sprint instead:'
      lines << '  start_at first_time_added_to_active_sprint'
    end
    lines.join "\n"
  end

  # A team-managed ("simple") board can be scrum- or kanban-flavoured depending on its sprints
  # feature; the bare "simple" from Jira doesn't say which, so spell it out.
  def board_kind_label board
    return board.board_type unless board.board_type == 'simple'

    board.scrum? ? 'team-managed, uses sprints' : 'team-managed, no sprints'
  end

  def format_status status
    "#{status.name.inspect}:#{status.id} (#{status.category.name})"
  end

  def info key, name_filter:
    selected = []
    file_system.log_only = true
    each_project_config(name_filter: name_filter) do |project|
      project.evaluate_next_level

      project.run load_only: true
      selected.concat matching_issues_in(project, key)
    rescue => e # rubocop:disable Style/RescueStandardError
      # This happens when we're attempting to load an aggregated project because it hasn't been
      # properly initialized. Since we don't care about aggregated projects, we just ignore it.
      raise unless e.message.start_with? 'This is an aggregated project and issues should have been included'
    end
    file_system.log_only = false

    if selected.empty?
      file_system.log "No issues found to match #{key.inspect}"
    else
      selected.each do |project, issue|
        file_system.log "\nProject #{project.name}", also_write_to_stderr: true
        file_system.log issue.dump, also_write_to_stderr: true
      end
    end
  end

  def matching_issues_in project, key
    matches = []
    project.issues.each do |issue|
      matches << [project, issue] if key == issue.key
      issue.subtasks.each do |subtask|
        matches << [project, subtask] if key == subtask.key
      end
    end
    matches
  end

  def stitch stitch_file
    Stitcher.new(file_system: file_system).run(stitch_file: stitch_file)
  end

  def each_project_config name_filter:
    @project_configs.each do |project|
      yield project if project.name.nil? || File.fnmatch(name_filter, project.name)
    end
  end

  def downloading?
    @downloading
  end

  def project name: nil, &block
    raise 'jira_config not set' if @jira_config.nil?

    @project_configs << ProjectConfig.new(
      exporter: self, target_path: @target_path, jira_config: @jira_config, block: block, name: name
    )
  end

  def xproject *args; end

  def target_path path = nil
    unless path.nil?
      @target_path = path
      @target_path += File::SEPARATOR unless @target_path.end_with? File::SEPARATOR
      FileUtils.mkdir_p @target_path
    end
    @target_path
  end

  def jira_config filename = nil
    if filename
      @jira_config = file_system.load_json(filename, fail_on_error: false)
      raise "Unable to load Jira configuration file and cannot continue: #{filename.inspect}" if @jira_config.nil?

      match = %r{^(?<base_url>.+)/+$}.match(@jira_config['url'])
      @jira_config['url'] = match[:base_url] if match
    end
    @jira_config
  end

  def timezone_offset offset = nil
    @timezone_offset = offset unless offset.nil?
    @timezone_offset
  end

  def holiday_dates *args
    unless args.empty?
      dates = []
      args.each do |arg|
        if /^(?<from>\d{4}-\d{2}-\d{2})\.\.(?<to>\d{4}-\d{2}-\d{2})$/ =~ arg
          Date.parse(from).upto(Date.parse(to)).each { |date| dates << date }
        else
          dates << Date.parse(arg)
        end
      end
      @holiday_dates = dates
    end
    @holiday_dates
  end
end
