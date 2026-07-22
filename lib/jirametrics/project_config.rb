# frozen_string_literal: true

require 'time'
require 'jirametrics/status_collection'

class ProjectConfig
  attr_reader :target_path, :jira_config, :all_boards, :possible_statuses,
    :download_config, :file_configs, :exporter, :data_version, :name, :board_configs,
    :settings, :aggregate_config, :discarded_changes_data, :users, :fix_versions
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
    @fix_versions = []
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
    load_fix_versions
    load_users
    resolve_blocked_stalled_status_settings
  end

  def run load_only: false
    return if @exporter.downloading?

    load_data unless aggregated_project?

    return if load_only

    anonymize_data if @anonymizer_needed

    @file_configs.each(&:run)
  end

  def load_settings
    # This is the weird exception that we don't ever want mocked out so we skip FileSystem entirely.
    settings = JSON.parse(File.read(File.join(__dir__, 'settings.json'), encoding: 'UTF-8'))

    settings['blocked_statuses'] = StatusCollection.new
    settings['stalled_statuses'] = StatusCollection.new

    stringify_keys(settings)
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

  def aggregate_project_names
    return [] unless aggregated_project?

    @aggregate_config.included_projects.filter_map(&:name)
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

    # There can only be one of these
    if @file_prefix
      raise "file_prefix can only be set once. Was #{@file_prefix.inspect} and now changed to #{prefix.inspect}."
    end

    raise_if_prefix_already_used(prefix)

    @file_prefix = prefix

    # Yes, this is a wierd place to be initializing this. Unfortunately, it has to happen after the file_prefix
    # is set but before anything inside the project block is run. If only we had made file_prefix an attribute
    # on project, we wouldn't have this ugliness. 🤷‍♂️
    load_status_category_mappings
    load_status_history
    load_all_boards

    @file_prefix
  end

  def validate_discard_status status_name
    return if status_name == :backlog
    return if possible_statuses.empty? # not yet downloaded; skip validation

    found = possible_statuses.find_all_by_name status_name
    return unless found.empty?

    raise "discard_changes_before: Status #{status_name.inspect} not found. " \
      "Possible statuses are: #{possible_statuses}"
  end

  def raise_if_prefix_already_used prefix
    @exporter.project_configs.each do |project|
      next unless project.get_file_prefix(raise_if_not_set: false) == prefix && project.target_path == target_path

      raise "Project #{name.inspect} specifies file prefix #{prefix.inspect}, " \
        "but that is already used by project #{project.name.inspect} in the same target path #{target_path.inspect}. " \
        'This is almost guaranteed to be too much copy and paste in your configuration. ' \
        'File prefixes must be unique within a directory.'
    end
  end

  def get_file_prefix raise_if_not_set: true
    if @file_prefix.nil? && raise_if_not_set
      raise 'file_prefix has not been set yet. Move it to the top of the project declaration.'
    end

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
      status_id = guess_status_id_for status, category
      return if status_id.nil? # no id could be guessed; the mapping is ignored (already warned)
    end

    found_category = resolve_category category, category_id
    add_possible_status(
      Status.new(
        name: status, id: status_id,
        category_name: category, category_id: found_category.id, category_key: found_category.key
      )
    )
  end

  # When a status is named but not given an id, guess it from the ids seen under that name across all
  # issue histories. Returns nil (after warning) when none is found, or raises when it's ambiguous.
  def guess_status_id_for status, category
    guesses = find_ids_by_status_name_across_all_issues status
    if guesses.empty?
      file_system.warning "For status_category_mapping status: #{status.inspect}, category: #{category.inspect}\n" \
        "Cannot guess status id for #{status.inspect} as no statuses found anywhere in the issues " \
        "histories with that name. Since we can't find it, you probably don't need this mapping anymore so we're " \
        "going to ignore it. If you really want it, then you'll need to specify a status id."
      return nil
    end

    if guesses.size > 1
      raise "Cannot guess status id as there are multiple ids for the name #{status.inspect}. Perhaps it's one " \
        "of #{guesses.to_a.sort.inspect}. If you need this mapping then you must specify the status_id."
    end

    status_id = guesses.first
    file_system.log "status_category_mapping for #{status.inspect} has been mapped to id #{status_id}. " \
      "If that's incorrect then specify the status_id."
    status_id
  end

  # Find the single status category with the given name, raising if there are none, several, or a
  # supplied id that disagrees with the one we found.
  def resolve_category category, category_id
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

    found_category
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
      match = file.match(/^#{get_file_prefix}_board_(?<board_id>\d+)_configuration\.json$/)
      next unless match

      board_id = match[:board_id].to_i
      load_board board_id: board_id, filename: "#{@target_path}#{file}"
    end
  end

  def load_board board_id:, filename:
    raw = file_system.load_json(filename)

    features_filename = File.join(@target_path, "#{get_file_prefix}_board_#{board_id}_features.json")
    features = if file_system.file_exist?(features_filename)
                 BoardFeature.from_raw(file_system.load_json(features_filename))
               else
                 []
               end

    board = Board.new(raw: raw, possible_statuses: @possible_statuses, features: features)
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
  # This is an optional enrichment file. A malformed one surfaces as anything from a JSON::ParserError to
  # a TypeError/NoMethodError out of Status.from_raw, so we deliberately catch broadly, warn, and carry on
  # without it rather than fail the whole export. The exception itself goes to the log file only (via
  # `more`) so we don't lose it, while the console stays uncluttered.
  rescue => e # rubocop:disable Style/RescueStandardError
    file_system.warning(
      'Unable to load status history. If this is because of a malformed file then it should be ' \
      'fixed on the next download.',
      more: [e.message, *e.backtrace].join("\n")
    )
  end

  def load_sprints
    file_system.foreach(@target_path) do |file|
      next unless file =~ /^#{get_file_prefix}_board_(\d+)_sprints_\d+.json$/

      board_id = $1.to_i
      file_path = File.join(@target_path, file)
      board = @all_boards[board_id]
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

  def load_fix_versions
    filename = File.join(@target_path, "#{get_file_prefix}_fix_versions.json")
    return unless file_system.file_exist?(filename)

    @fix_versions = file_system.load_json(filename).map { |raw| FixVersion.new(raw) }
  end

  def load_project_metadata
    filename = File.join @target_path, "#{get_file_prefix}_meta.json"
    json = file_system.load_json(filename)

    @data_version = json['version'] || 1

    start = to_time(json['date_start'] || json['time_start']) # date_start is the current format. Time is the old.
    stop  = to_time(json['date_end'] || json['time_end'], end_of_day: true)

    @time_range = clamp_to_no_earlier_than(start)..stop
    @jira_url = json['jira_url']
  rescue Errno::ENOENT
    file_system.log "Can't load #{filename}. Have you done a download?", also_write_to_stderr: true
    raise
  end

  # If the download was configured with a no_earlier_than, the data can't start before it.
  def clamp_to_no_earlier_than start
    return start unless download_config

    download_config.run
    no_earlier = download_config.no_earlier_than
    return start unless no_earlier

    no_earlier = to_time(no_earlier.to_s)
    [start, no_earlier].max
  end

  def load_users
    @users = []
    filename = File.join @target_path, "#{get_file_prefix}_users.json"
    return unless File.exist? filename

    json = file_system.load_json(filename)
    json.each { |user_data| @users << User.new(raw: user_data) }
  end

  def attach_github_prs
    filename = File.join(@target_path, "#{get_file_prefix}_github_prs.json")
    return unless File.exist?(filename)

    prs_by_issue_key = Hash.new { |h, k| h[k] = [] }
    file_system.load_json(filename).each do |raw|
      pr = PullRequest.new(raw: raw)
      pr.issue_keys.each { |key| prs_by_issue_key[key] << pr }
    end

    @issues.each { |issue| issue.github_prs = prs_by_issue_key[issue.key] }
  end

  def atlassian_document_format
    @atlassian_document_format ||= AtlassianDocumentFormat.new(
      users: @users, timezone_offset: exporter.timezone_offset
    )
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
    @issues = IssueCollection.new if @issues.nil?
    @all_boards ||= {}

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

      return @issues = IssueCollection.new if @exporter.downloading?
      raise 'No data found. Must do a download before an export' unless data_downloaded?

      load_data if all_boards.empty?

      issues_path = File.join @target_path, "#{get_file_prefix}_issues"
      # File.directory? is already false for a path that doesn't exist, so no need to also check File.exist?.
      unless File.directory?(issues_path)
        file_system.log "Can't find directory #{issues_path}. Has a download been done?", also_write_to_stderr: true
        return IssueCollection.new
      end

      @issues = build_issues_from_directory(issues_path)
      attach_github_prs
    end

    @issues
  end

  def build_issues_from_directory issues_path
    file_system.diagnostic "Loading issues from #{issues_path}"
    issues = load_issues_from_issues_directory path: issues_path, timezone_offset: exporter.timezone_offset
    file_system.diagnostic "Loaded #{issues.size} issues from disk"

    attach_related_issues issues

    # We'll have some issues that are in the list that weren't part of the initial query. Once we've
    # attached them in the appropriate places, remove any that aren't part of that initial set.
    issues.select!(&:in_initial_query?)
    file_system.diagnostic "Retained #{issues.size} primary issues"
    issues
  end

  # Wire up subtasks, parents and linked issues now that we have the whole set loaded.
  def attach_related_issues issues
    file_system.diagnostic 'Starting attach phase'
    issues_by_key = issues.to_h { |issue| [issue.key, issue] }
    issues.each do |issue|
      attach_subtasks issue: issue, issues_by_key: issues_by_key
      attach_parent issue: issue, issues_by_key: issues_by_key
      attach_linked_issues issue: issue, issues_by_key: issues_by_key
    end
    file_system.diagnostic 'Attach phase complete'
  end

  def attach_subtasks issue:, issues_by_key:
    issue.raw['fields']['subtasks']&.each do |subtask_element|
      subtask = issues_by_key[subtask_element['key']]
      issue.subtasks << subtask if subtask
    end
  end

  def attach_parent issue:, issues_by_key:
    parent_key = issue.parent_key
    issue.parent = issues_by_key[parent_key] if parent_key
  end

  def attach_linked_issues issue:, issues_by_key:
    issue.issue_links.each do |link|
      if link.other_issue.artificial?
        other = issues_by_key[link.other_issue.key]
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
    issues = IssueCollection.new
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
          raise "The board declaration for board #{board.id} must come before the " \
            "first usage of 'issues' in the configuration"
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
    group_files_by_issue_key(path).values.to_h { |list| resolve_key_files(list, path) }
  end

  def group_files_by_issue_key path
    hash = {}
    file_system.foreach(path) do |filename|
      # Matches either FAKE-123.json or FAKE-123-456.json
      if /^(?<key>[^-]+-\d+)(?<_>-(?<board_id>\d+))?\.json$/ =~ filename
        (hash[key] ||= []) << [filename, board_id&.to_i || :unknown]
      end
    end
    hash
  end

  # Given all the files that share an issue key, returns the [filename, board_ids] pair for the result.
  # A lone file keeps its own board id; when the same issue was exported for several boards we keep the
  # newest file and associate every known board id with it.
  def resolve_key_files list, path
    if list.size == 1
      filename, board_id = *list.first
      [filename, board_id == :unknown ? board_id : [board_id]]
    else
      newest_filename, = list.max_by { |filename, _| File.mtime(File.join(path, filename)) }
      board_ids = list.filter_map { |_, board_id| board_id unless board_id == :unknown }
      [newest_filename, board_ids]
    end
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
    block = discard_block_for(status_becomes) if status_becomes
    apply_discard_block block
  end

  # Build the block that, for an issue, returns the time it most recently entered one of the
  # status_becomes statuses (or nil).
  def discard_block_for status_becomes
    status_becomes = [status_becomes] unless status_becomes.is_a? Array
    status_becomes.each { |status_name| validate_discard_status status_name }
    ->(issue) { last_matching_status_time issue, status_becomes }
  end

  def last_matching_status_time issue, status_becomes
    trigger_status_ids = trigger_status_ids_for issue, status_becomes
    return if trigger_status_ids.empty?

    time = nil
    issue.status_changes.each do |change|
      time = change.time if trigger_status_ids.include?(change.value_id) # && change.artificial? == false
    end
    time
  end

  def trigger_status_ids_for issue, status_becomes
    status_becomes.collect do |status_name|
      if status_name == :backlog
        issue.board.backlog_statuses
      else
        possible_statuses.find_all_by_name status_name
      end
    end.flatten.collect(&:id)
  end

  def apply_discard_block block
    cycletimes_touched = Set.new
    file_system.diagnostic "discard_changes_before: processing #{issues.size} issues"
    issues.each { |issue| discard_changes_for_issue issue, block, cycletimes_touched }
    cycletimes_touched.each(&:flush_cache)
  end

  def discard_changes_for_issue issue, block, cycletimes_touched
    cutoff_time = block.call(issue)
    return if cutoff_time.nil?

    original_start_time = issue.started_stopped_times.first
    return if original_start_time.nil?

    issue.discard_changes_before cutoff_time
    cycletimes_touched << issue.board.cycletime

    return unless cutoff_time # a user-supplied block may return false rather than nil
    return if original_start_time > cutoff_time # ie the cutoff would have made no difference.

    (@discarded_changes_data ||= []) << {
      cutoff_time: cutoff_time,
      original_start_time: original_start_time,
      issue: issue
    }
  end

  def stringify_keys value
    case value
    when Hash then value.transform_keys(&:to_s).transform_values { |v| stringify_keys(v) }
    when Array then value.map { |v| stringify_keys(v) }
    else value
    end
  end

  def resolve_blocked_stalled_status_settings
    %w[blocked_statuses stalled_statuses].each do |key|
      next if @settings[key].is_a?(StatusCollection)

      collection = StatusCollection.new
      @settings[key].each do |identifier|
        statuses = @possible_statuses.find_all_by_name(identifier)
        if statuses.empty?
          file_system.warning "Status #{identifier.inspect} in #{key} not found. Ignoring."
        else
          statuses.each { |status| collection << status }
        end
      end
      @settings[key] = collection
    end
  end
end
