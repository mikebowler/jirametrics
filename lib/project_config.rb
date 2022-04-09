# frozen_string_literal: true

class ProjectConfig
  include DiscardChangesBefore

  attr_reader :target_path, :jira_config, :all_board_columns, :possible_statuses,
    :download_config, :file_configs, :exporter, :data_version, :sprints_by_board
  attr_accessor :time_range

  def initialize exporter:, jira_config:, block:, target_path: '.'
    @exporter = exporter
    @block = block
    @file_configs = []
    @download_config = nil
    @target_path = target_path
    @jira_config = jira_config
    @possible_statuses = []
    @all_board_columns = {}
    @sprints_by_board = {}
  end

  def evaluate_next_level
    instance_eval(&@block)
  end

  def run
    load_project_metadata
    load_all_board_columns
    load_status_category_mappings
    load_sprints
    anonymize_data if @anonymizer_needed

    @file_configs.each do |file_config|
      file_config.run
    end
  end

  def download &block
    raise 'Not allowed to have multiple download blocks in one project' if @download_config

    @download_config = DownloadConfig.new project_config: self, block: block
  end

  def file &block
    @file_configs << FileConfig.new(project_config: self, block: block)
  end

  def file_prefix prefix = nil
    @file_prefix = prefix unless prefix.nil?
    @file_prefix
  end

  def status_category_mapping type: nil, status:, category:
    puts "Deprecated: ProjectConfig.status_category_mapping no longer needs a type: #{type.inspect}" if type

    status_object = find_status(name: status)
    if status_object
      puts "Status/Category mapping was already present. Ignoring redefinition: #{status_object}"
      return
    end

    add_possible_status Status.new(name: status, id: nil, category_name: category, category_id: nil)
  end

  def load_all_board_columns
    Dir.foreach(@target_path) do |file|
      next unless file =~ /^#{@file_prefix}_board_(\d+)_configuration\.json$/

      board_id = $1
      load_board_columns board_id: board_id, filename: "#{@target_path}#{file}"
    end
  end

  def load_board_columns board_id:, filename:
    json = JSON.parse(File.read(filename))
    @all_board_columns[board_id.to_i] = json['columnConfig']['columns'].collect do |column|
      BoardColumn.new column
    end
  end

  def category_for type: nil, status_name:
    status = find_status name: status_name
    raise_with_message_about_missing_category_information if status.nil? || status.category_name.nil?

    status.category_name
  end

  def raise_with_message_about_missing_category_information
    message = String.new
    message << 'Could not determine categories for some of the statuses used in this data set.\n\n' \
      'If you specify a project: then we\'ll ask Jira for those mappings. If you\'ve done that' \
      ' and we still don\'t have the right mapping, which is possible, then use the' \
      " 'status_category_mapping' declaration in your config to manually add one.\n\n" \
      ' The mappings we do know about are below:'

    @possible_statuses.each do |status|
      message << "\n  type: #{status.type.inspect}, status: #{status.name.inspect}, " \
        "category: #{status.category_name.inspect}'"
    end

    message << "\n\nThe ones we're missing are the following:"

    missing_statuses = []
    issues.each do |issue|
      issue.changes.each do |change|
        next unless change.status?

        missing_statuses << change.value unless find_status(name: change.value)
      end
    end

    missing_statuses.uniq.each do |status_name|
      message << "\n  status: #{status_name.inspect}, category: <unknown>"
    end

    raise message
  end

  def load_status_category_mappings
    filename = "#{@target_path}/#{file_prefix}_statuses.json"
    # We may not always have this file. Load it if we can.
    return unless File.exist? filename

    status_json_snippets = []

    json = JSON.parse(File.read(filename))
    if json[0]['statuses']
      # Response from /api/2/{project_code}/status
      json.each do |type_config|
        status_json_snippets += type_config['statuses']
      end
    else
      # Response from /api/2/status
      status_json_snippets = json
    end

    status_json_snippets.each do |snippet|
      category_config = snippet['statusCategory']
      status_name = snippet['name']
      add_possible_status Status.new(
        name: status_name,
        id: snippet['id'],
        category_name: category_config['name'],
        category_id: category_config['id']
      )
    end
  end

  def load_sprints
    Dir.foreach(@target_path) do |file|
      next unless file =~ /#{file_prefix}_board_(\d+)_sprints_\d+/

      board_id = $1.to_i
      @sprints_by_board[board_id] = JSON.parse(File.read("#{target_path}#{file}"))['values'].collect do |json|
        Sprint.new raw: json
      end
    end
  end

  def add_possible_status status
    existing_status = find_status(name: status.name)

    if existing_status
      if existing_status.category_name != status.category_name
        raise "Redefining status category #{status} with #{existing_status}. Was one set in the config?"
      end

      return
    end

    @possible_statuses << status
  end

  def find_status name:
    @possible_statuses.find { |status| status.name == name }
  end

  def load_project_metadata
    filename = "#{@target_path}/#{file_prefix}_meta.json"
    json = JSON.parse(File.read(filename))

    @data_version = json['version'] || 1

    start = json['date_start'] || json['time_start'] # date_start is the current format. Time is the old.
    stop  = json['date_end'] || json['time_end']
    @time_range = (DateTime.parse(start)..DateTime.parse(stop))
  rescue Errno::ENOENT
    puts "== Can't load files from the target directory. Did you forget to download first? =="
    raise
  end

  def board_columns board_id: nil
    all_board_columns = @all_board_columns
    if board_id.nil?
      unless all_board_columns.size == 1
        message = "If the board_id isn't set then we look for all board configurations in the target" \
          ' directory. '
        if all_board_columns.empty?
          message += ' In this case, we couldn\'t find any configuration files in the target directory.'
        else
          message += 'If there is only one, we use that. In this case we found configurations for' \
            " the following board ids and this is ambiguous: #{all_board_columns.keys}"
        end
        raise message
      end

      board_id = all_board_columns.keys[0]
    end
    board_columns = all_board_columns[board_id]

    raise "Unable to find configuration for board_id: #{board_id}" if board_columns.nil?

    board_columns
  end

  def issues
    unless @issues
      timezone_offset = exporter.timezone_offset

      issues_path = "#{@target_path}#{file_prefix}_issues/"
      if File.exist?(issues_path) && File.directory?(issues_path)
        issues = load_issues_from_issues_directory path: issues_path, timezone_offset: timezone_offset
      elsif File.exist?(@target_path) && File.directory?(@target_path)
        issues = load_issues_from_target_directory path: @target_path, timezone_offset: timezone_offset
      else
        puts "Can't find issues in either #{path} or #{@target_path}"
      end
      @issues = issues
    end

    @issues
  end

  def load_issues_from_target_directory path:, timezone_offset:
    puts 'Deprecated: issues in the target directory. Download again and this should fix itself.'

    issues = []
    Dir.foreach(path) do |filename|
      if filename =~ /#{file_prefix}_\d+\.json/
        content = JSON.parse File.read("#{path}#{filename}")
        content['issues'].each { |issue| issues << Issue.new(raw: issue, timezone_offset: timezone_offset) }
      end
    end
    issues
  end

  def load_issues_from_issues_directory path:, timezone_offset:
    issues = []
    Dir.foreach(path) do |filename|
      if filename =~ /-\d+\.json$/
        content = JSON.parse File.read("#{path}#{filename}")
        issues << Issue.new(raw: content, timezone_offset: timezone_offset)
      end
    end
    issues
  end

  def anonymize
    @anonymizer_needed = true
  end

  def anonymize_data
    Anonymizer.new(project_config: self).run
  end

  def discard_changes_before_hook issues_cutoff_times
    issues_cutoff_times.each do |issue, cutoff_time|
      days = (cutoff_time.to_date - issue.changes.first.time.to_date).to_i + 1
      message = "#{issue.key}(#{issue.type}) discarding #{days} "
      if days == 1
        message << "day of data on #{cutoff_time.to_date}"
      else
        message << "days of data from #{issue.changes.first.time.to_date} to #{cutoff_time.to_date}"
      end
      puts message
    end
    puts "Discarded data from #{issues_cutoff_times.count} issues out of a total #{issues.size}"
  end
end
