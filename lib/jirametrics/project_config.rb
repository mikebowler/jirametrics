# frozen_string_literal: true

require 'time'
require 'jirametrics/status_collection'

class ProjectConfig
  attr_reader :target_path, :jira_config, :all_boards, :possible_statuses,
    :download_config, :file_configs, :exporter, :data_version, :name, :board_configs,
    :settings, :aggregate_config, :discarded_changes_data
  attr_accessor :time_range, :jira_url, :id

  def initialize exporter:, jira_config:, block:, target_path: '.', name: '', id: nil
    @exporter = exporter
    @block = block
    @file_configs = []
    @download_config = nil
    @target_path = target_path
    @jira_config = jira_config
    @possible_statuses = StatusCollection.new
    @name = name
    @board_configs = []
    @all_boards = {}
    @settings = load_settings
    @id = id
    @has_loaded_data = false
  end

  def evaluate_next_level
    instance_eval(&@block) if @block
  end

  def data_downloaded?
    file_system.file_exist? File.join(@target_path, "#{get_file_prefix}_meta.json")
  end

  def load_data
    return if @has_loaded_data

    @has_loaded_data = true
    @id = guess_project_id
    load_project_metadata
    load_sprints
  end

  def run load_only: false
    return if @exporter.downloading?

    load_data unless aggregated_project?
    anonymize_data if @anonymizer_needed

    return if load_only

    @file_configs.each do |file_config|
      file_config.run
    end
  end

  def load_settings
    # This is the weird exception that we don't ever want mocked out so we skip FileSystem entirely.
    JSON.parse(File.read(File.join(__dir__, 'settings.json'), encoding: 'UTF-8'))
  end

  def guess_project_id
    return @id if @id

    previous_id = nil
    @all_boards.each_value do |board|
      project_id = board.project_id

      # If the id is ambiguous then return nil for now. The user will get an error later
      # in the case where we need it to be unambiguous. Sometimes we don't care and there's
      # no point forcing the user to enter a project id if we don't need it.
      return nil if previous_id && project_id && previous_id != project_id

      previous_id = project_id if project_id
    end
    previous_id
  end

  def aggregated_project?
    !!@aggregate_config
  end

  def download &block
    raise 'Not allowed to have multiple download blocks in one project' if @download_config
    raise 'Not allowed to have both an aggregate and a download section. Pick only one.' if @aggregate_config

    @download_config = DownloadConfig.new project_config: self, block: block
  end

  def file &block
    @file_configs << FileConfig.new(project_config: self, block: block)
  end

  def aggregate &block
    raise 'Not allowed to have multiple aggregate blocks in one project' if @aggregate_config
    raise 'Not allowed to have both an aggregate and a download section. Pick only one.' if @download_config

    @aggregate_config = AggregateConfig.new project_config: self, block: block

    # Processing of aggregates should only happen during the export
    return if @exporter.downloading?

    @aggregate_config.evaluate_next_level
  end

  def board id:, &block
    config = BoardConfig.new(id: id, block: block, project_config: self)
    config.run if data_downloaded?
    @board_configs << config
  end

  def file_prefix prefix
    # The file_prefix has to be set before almost everything else. It really should have been an attribute
    # on the project declaration itself. Hindsight is 20/20.
    if @file_prefix
      raise "file_prefix should only be set once. Was #{@file_prefix.inspect} and now changed to #{prefix.inspect}."
    end

    @file_prefix = prefix

    # Yes, this is a wierd place to be initializing this. Unfortunately, it has to happen after the file_prefix
    # is set but before anything inside the project block is run. If only we had made file_prefix an attribute
    # on project, we wouldn't have this ugliness. 🤷‍♂️
    load_status_category_mappings
    load_status_history
    load_all_boards

    @file_prefix
  end

  def get_file_prefix # rubocop:disable Naming/AccessorMethodName
    raise 'file_prefix has not been set yet. Move it to the top of the project declaration.' unless @file_prefix

    @file_prefix
  end

  # Walk across all the issues and find any status with that name. Return a list of ids that match.
  def find_ids_by_status_name_across_all_issues name
    ids = Set.new

    issues.each do |issue|
      issue.changes.each do |change|
        next unless change.status?

        ids << change.value_id.to_i if change.value == name
        ids << change.old_value_id.to_i if change.old_value == name
      end
    end
    ids.to_a
  end

  def status_category_mapping status:, category:
    return if @exporter.downloading?

    status, status_id = possible_statuses.parse_name_id status
    category, category_id = possible_statuses.parse_name_id category

    if status_id.nil?
      guesses = find_ids_by_status_name_across_all_issues status
      if guesses.empty?
        file_system.warning "For status_category_mapping status: #{status.inspect}, category: #{category.inspect}\n" \
          "Cannot guess status id for #{status.inspect} as no statuses found anywhere in the issues " \
          "histories with that name. Since we can't find it, you probably don't need this mapping anymore so we're " \
          "going to ignore it. If you really want it, then you'll need to specify a status id."
        return
      end

      if guesses.size > 1
        raise "Cannot guess status id as there are multiple ids for the name #{status.inspect}. Perhaps it's one " \
          "of #{guesses.to_a.sort.inspect}. If you need this mapping then you must specify the status_id."
      end

      status_id = guesses.first
      file_system.log "status_category_mapping for #{status.inspect} has been mapped to id #{status_id}. " \
        "If that's incorrect then specify the status_id."
    end

    possible_categories = possible_statuses.find_all_categories_by_name category
    if possible_categories.empty?
      all = possible_statuses.find_all_categories.join(', ')
      raise "No status categories found for name #{category.inspect} in [#{all}]. " \
        'Either fix the name or add an ID.'
    elsif possible_categories.size > 1
      # Theoretically impossible and yet we've seen wierder things out of Jira so we're prepared.
      raise "More than one status category found with the name #{category.inspect} in " \
        "[#{possible_categories.join(', ')}]. Either fix the name or add an ID"
    end

    found_category = possible_categories.first

    if category_id && category_id != found_category.id
      raise "ID is incorrect for status category #{category.inspect}. Did you mean #{found_category.id}?"
    end

    add_possible_status(
      Status.new(
        name: status, id: status_id,
        category_name: category, category_id: found_category.id, category_key: found_category.key
      )
    )
  end

  def add_possible_status status
    existing_status = @possible_statuses.find_by_id status.id

    if existing_status && existing_status.name != status.name
      raise "Attempting to redefine the name for status #{status.id} from " \
        "#{existing_status.name.inspect} to #{status.name.inspect}"
    end

    # If it isn't there, add it and go.
    return @possible_statuses << status unless existing_status

    unless status == existing_status
      raise "Redefining status category for status #{status}. " \
        "original: #{existing_status.category}, " \
        "new: #{status.category}"
    end

    # We're registering one we already knew about. This may happen if someone specified a status_category_mapping
    # for something that was already returned from jira.
    #
    # You may be looking at this code and thinking of changing it to spit out a warning since obviously
    # the user has made a mistake. Unfortunately, they may not have made any mistake. Due to inconsistency with the
    # status API, it's possible for two different people to make a request to the same API at the same time and get
    # back a different set of statuses. So that means that some people might need more status/categories mappings than
    # other people for exactly the same instance. See this article for more on that API:
    # https://agiletechnicalexcellence.com/2024/04/12/jira-api-statuses.html
    existing_status
  end

  def load_all_boards
    Dir.foreach(@target_path) do |file|
      next unless file =~ /^#{get_file_prefix}_board_(\d+)_configuration\.json$/

      board_id = $1.to_i
      load_board board_id: board_id, filename: "#{@target_path}#{file}"
    end
  end

  def load_board board_id:, filename:
    board = Board.new(
      raw: file_system.load_json(filename), possible_statuses: @possible_statuses
    )
    board.project_config = self
    @all_boards[board_id] = board
  end

  def load_status_category_mappings
    filename = File.join @target_path, "#{get_file_prefix}_statuses.json"
    return unless file_system.file_exist? filename

    file_system
      .load_json(filename)
      .map { |snippet| Status.from_raw(snippet) }
      .each { |status| add_possible_status status }
  end

  def load_status_history
    filename = File.join @target_path, "#{get_file_prefix}_status_history.json"
    return unless file_system.file_exist? filename

    file_system.log '  Loading historical statuses', also_write_to_stderr: true
    file_system
      .load_json(filename)
      .map { |snippet| Status.from_raw(snippet) }
      .each { |status| possible_statuses.historical_status_mappings[status.to_s] = status.category }

    possible_statuses
  rescue => e # rubocop:disable Style/RescueStandardError
    file_system.warning "Unable to load status history due to #{e.message.inspect}. If this is because of a " \
      'malformed file then it should be fixed on the next download.'
  end

  def load_sprints
    file_system.foreach(@target_path) do |file|
      next unless file =~ /^#{get_file_prefix}_board_(\d+)_sprints_\d+.json$/

      file_path = File.join(@target_path, file)
      board = @all_boards[$1.to_i]
      unless board
        @exporter.file_system.log(
          'Found sprint data but can\'t find a matching board in config. ' \
            "File: #{file_path}, Boards: #{@all_boards.keys.sort}"
        )
        next
      end

      timezone_offset = exporter.timezone_offset
      file_system.load_json(file_path)['values']&.each do |json|
        board.sprints << Sprint.new(raw: json, timezone_offset: timezone_offset)
      end
    end

    @all_boards.each_value do |board|
      board.sprints.sort_by!(&:id)
    end
  end

  def load_project_metadata
    filename = File.join @target_path, "#{get_file_prefix}_meta.json"
    json = file_system.load_json(filename)

    @data_version = json['version'] || 1

    start = to_time(json['date_start'] || json['time_start']) # date_start is the current format. Time is the old.
    stop  = to_time(json['date_end'] || json['time_end'], end_of_day: true)

    # If no_earlier_than was set then make sure it's applied here.
    if download_config
      download_config.run
      no_earlier = download_config.no_earlier_than
      if no_earlier
        no_earlier = to_time(no_earlier.to_s)
        start = no_earlier if start < no_earlier
      end
    end

    @time_range = start..stop

    @jira_url = json['jira_url']
  rescue Errno::ENOENT
    file_system.log "Can't load #{filename}. Have you done a download?", also_write_to_stderr: true
    raise
  end

  def to_time string, end_of_day: false
    time = end_of_day ? '23:59:59' : '00:00:00'
    string = "#{string}T#{time}#{exporter.timezone_offset}" if string.match?(/^\d{4}-\d{2}-\d{2}$/)
    Time.parse string
  end

  def guess_board_id
    return nil if aggregated_project?

    unless all_boards&.size == 1
      message = "If the board_id isn't set then we look for all board configurations in the target" \
        ' directory. '
      if all_boards.empty?
        message += ' In this case, we couldn\'t find any configuration files in the target directory.'
      else
        message += 'If there is only one, we use that. In this case we found configurations for' \
          " the following board ids and this is ambiguous: #{all_boards.keys}"
      end
      raise message
    end
    all_boards.keys[0]
  end

  def find_board_by_id board_id = nil
    board = all_boards[board_id || guess_board_id]

    raise "Unable to find configuration for board_id: #{board_id}" if board.nil?

    board
  end

  # To be used by the aggregate_config only. Not intended to be part of the public API
  def add_issues issues_list
    @issues = [] if @issues.nil?
    @all_boards = {}

    issues_list.each do |issue|
      @issues << issue
      board = issue.board
      @all_boards[board.id] = board unless @all_boards[board.id]
    end
  end

  def issues
    unless @issues
      if aggregated_project?
        raise 'This is an aggregated project and issues should have been included with the include_issues_from ' \
          'declaration but none are here. Check your config.'
      end

      return @issues = [] if @exporter.downloading?
      raise 'No data found. Must do a download before an export' unless data_downloaded?

      load_data if all_boards.empty?

      timezone_offset = exporter.timezone_offset

      issues_path = File.join @target_path, "#{get_file_prefix}_issues"
      if File.exist?(issues_path) && File.directory?(issues_path)
        issues = load_issues_from_issues_directory path: issues_path, timezone_offset: timezone_offset
      else
        file_system.log "Can't find directory #{issues_path}. Has a download been done?", also_write_to_stderr: true
        return []
      end

      # Attach related issues
      issues.each do |i|
        attach_subtasks issue: i, all_issues: issues
        attach_parent issue: i, all_issues: issues
        attach_linked_issues issue: i, all_issues: issues
      end

      # We'll have some issues that are in the list that weren't part of the initial query. Once we've
      # attached them in the appropriate places, remove any that aren't part of that initial set.
      @issues = issues.select { |i| i.in_initial_query? }
    end

    @issues
  end

  def attach_subtasks issue:, all_issues:
    issue.raw['fields']['subtasks']&.each do |subtask_element|
      subtask_key = subtask_element['key']
      subtask = all_issues.find { |i| i.key == subtask_key }
      issue.subtasks << subtask if subtask
    end
  end

  def attach_parent issue:, all_issues:
    parent_key = issue.parent_key
    parent = all_issues.find { |i| i.key == parent_key }
    issue.parent = parent if parent
  end

  def attach_linked_issues issue:, all_issues:
    issue.issue_links.each do |link|
      if link.other_issue.artificial?
        other = all_issues.find { |i| i.key == link.other_issue.key }
        link.other_issue = other if other
      end
    end
  end

  def find_default_board
    default_board = all_boards.values.first
    raise "No boards found for project #{name.inspect}" if all_boards.empty?

    if all_boards.size != 1
      file_system.log "Multiple boards are in use for project #{name.inspect}. " \
        "Picked #{default_board.name.inspect} to attach issues to.", also_write_to_stderr: true
    end
    default_board
  end

  def load_issues_from_issues_directory path:, timezone_offset:
    issues = []
    default_board = nil

    group_filenames_and_board_ids(path: path).each do |filename, board_ids|
      content = file_system.load_json(File.join(path, filename))
      if board_ids == :unknown
        boards = [(default_board ||= find_default_board)]
      else
        boards = board_ids.collect { |b| all_boards[b] }
      end

      boards.each do |board|
        if board.cycletime.nil?
          raise "The board declaration for board #{board.id} must come before the first usage of 'issues' in the configuration"
        end
        issues << Issue.new(raw: content, timezone_offset: timezone_offset, board: board)
      end
    end

    issues
  end

  # Scan through the issues directory (path), select the filenames to be loaded and map them to board ids.
  # It's ok if there are multiple files for the same issue. We load the newest one and map all the other
  # board ids appropriately.
  def group_filenames_and_board_ids path:
    hash = {}
    file_system.foreach(path) do |filename|
      # Matches either FAKE-123.json or FAKE-123-456.json
      if /^(?<key>[^-]+-\d+)(?<_>-(?<board_id>\d+))?\.json$/ =~ filename
        (hash[key] ||= []) << [filename, board_id&.to_i || :unknown]
      end
    end

    result = {}
    hash.values.collect do |list|
      if list.size == 1
        filename, board_id = *list.first
        result[filename] = board_id == :unknown ? board_id : [board_id]
      else
        max_time = nil
        max_board_id = nil
        max_filename = nil
        all_board_ids = []

        list.each do |filename, board_id|
          mtime = File.mtime(File.join(path, filename))
          if max_time.nil? || mtime > max_time
            max_time = mtime
            max_board_id = board_id
            max_filename = filename
          end
          all_board_ids << board_id unless board_id == :unknown
        end

        result[max_filename] = all_board_ids
      end
    end
    result
  end

  def anonymize
    @anonymizer_needed = true
  end

  def anonymize_data
    Anonymizer.new(project_config: self).run
  end

  def file_system
    @exporter.file_system
  end

  def discard_changes_before status_becomes: nil, &block
    if status_becomes
      status_becomes = [status_becomes] unless status_becomes.is_a? Array

      block = lambda do |issue|
        trigger_statuses = status_becomes.collect do |status_name|
          if status_name == :backlog
            issue.board.backlog_statuses
          else
            possible_statuses.find_all_by_name status_name
          end
        end.flatten

        next if trigger_statuses.empty?

        trigger_status_ids = trigger_statuses.collect(&:id)

        time = nil
        issue.status_changes.each do |change|
          time = change.time if trigger_status_ids.include?(change.value_id) # && change.artificial? == false
        end
        time
      end
    end

    issues.each do |issue|
      cutoff_time = block.call(issue)
      next if cutoff_time.nil?

      original_start_time = issue.board.cycletime.started_stopped_times(issue).first
      next if original_start_time.nil?

      issue.discard_changes_before cutoff_time

      next unless cutoff_time
      next if original_start_time > cutoff_time # ie the cutoff would have made no difference.

      (@discarded_changes_data ||= []) << {
        cutoff_time: cutoff_time,
        original_start_time: original_start_time,
        issue: issue
      }
    end
  end
end
