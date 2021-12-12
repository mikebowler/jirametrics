# frozen_string_literal: true

class Status
  attr_reader :name, :id, :type, :category_name, :category_id, :possible_statuses

  def initialize name:, id:, type:, category_name:, category_id:
    @name = name
    @id = id
    @type = type
    @category_name = category_name
    @category_id = category_id
  end
end

class ProjectConfig
  attr_reader :target_path, :jira_config, :all_board_columns, :possible_statuses,
    :download_config, :file_configs, :exporter, :date_range

  def initialize exporter:, target_path:, jira_config:, block:
    @exporter = exporter
    @block = block
    @file_configs = []
    @download_config = nil
    @target_path = target_path
    @jira_config = jira_config
    @possible_statuses = []
    @all_board_columns = {}
  end

  def evaluate_next_level
    instance_eval(&@block)
  end

  def run
    load_project_metadata
    load_all_board_configurations
    load_status_category_mappings
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

  def status_category_mapping type:, status:, category:

    status_object = @possible_statuses.find { |s| s.type == type && s.name == status }
    if status_object.nil?
      @possible_statuses << Status.new(name: status, id: nil, type: type, category_name: category, category_id: nil)
      return
    end

    # TODO: Raising an exception isn't ideal. Should probably accept it if it doesn't contradict what we already know
    raise "Status was already present: #{status}"
  end

  def load_all_board_configurations
    Dir.foreach(@target_path) do |file|
      next unless file =~ /^#{@file_prefix}_board_(\d+)_configuration\.json$/

      board_id = $1
      load_board_configuration board_id: board_id, filename: "#{@target_path}#{file}"
    end
  end

  def load_board_configuration board_id:, filename:
    json = JSON.parse(File.read(filename))
    @all_board_columns[board_id] = json['columnConfig']['columns'].collect do |column|
      BoardColumn.new column
    end
  end

  def category_for type:, status_name:, issue_id:
    status = @possible_statuses.find { |s| s.type == type && s.name == status_name }
    if status.nil? || status.category_name.nil?
      message = "Could not determine a category for type: #{type.inspect} and" \
        " status: #{status_name.inspect} on issue: #{issue_id}. If you" \
        ' specify a project: then we\'ll ask Jira for those mappings. If you\'ve done that' \
        ' and we still don\'t have the right mapping, which is possible, then use the' \
        ' "status_category_mapping" declaration in your config to manually add one.' \
        ' The mappings we do know about are below:'
      @possible_statuses.each do |status|
        message << "\n  Type: #{status.type.inspect}, Status: #{status.name.inspect}, Category: #{status.category_name.inspect}'"
      end

      raise message
    end
    status.category_name
  end

  def load_status_category_mappings
    filename = "#{@target_path}/#{file_prefix}_statuses.json"
    # We may not always have this file. Load it if we can.
    return unless File.exist? filename

    JSON.parse(File.read(filename)).each do |type_config|
      issue_type = type_config['name']
      type_config['statuses'].each do |status_config|
        category_config = status_config['statusCategory']
        @possible_statuses << Status.new(
          type: issue_type,
          name: status_config['name'], id: status_config['id'],
          category_name: category_config['name'], category_id: category_config['id']
        )
      end
    end
  end

  def load_project_metadata
    filename = "#{@target_path}/#{file_prefix}_meta.json"
    json = JSON.parse(File.read(filename))
    @date_range = (DateTime.parse(json['time_start'])..DateTime.parse(json['time_end']))
  end

  def board_metadata board_id: nil
    all_board_columns = @all_board_columns
    if board_id.nil?
      unless all_board_columns.size == 1
        message = "If the board_id isn't set then we look for all board configurations in the target" \
          ' directory. '
        if all_board_columns.empty?
          message += ' In this case, we couldn\'t find any configuration files in the target directory.'
        else
          message += 'If there is only one, we use that. In this case we found configurations for' \
            " the following board ids and this is ambiguous: #{all_board_columns}"
        end
        raise message
      end

      board_id = all_board_columns.keys[0]
    end
    board_columns = all_board_columns[board_id]

    raise "Unable to find configuration for board_id: #{board_id}" if board_columns.nil?

    board_columns
  end
end
