# frozen_string_literal: true

class ProjectConfig
  attr_reader :target_path, :jira_config, :all_board_columns, :status_category_mappings,
    :download_config, :file_configs, :exporter

  def initialize exporter:, target_path:, jira_config:, block:
    @exporter = exporter
    @block = block
    @file_configs = []
    @download_config = nil
    @target_path = target_path
    @jira_config = jira_config
    @status_category_mappings = {}
    @all_board_columns = {}
  end

  def evaluate_next_level
    instance_eval(&@block)
  end

  def run
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

  def file_prefix *arg
    @file_prefix = arg[0] unless arg.empty?
    @file_prefix
  end

  def status_category_mapping type:, status:, category:
    mappings = status_category_mappings
    mappings[type] = {} unless mappings[type]
    mappings[type][status] = category
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

  def category_for type:, status:, issue_id:
    category = @status_category_mappings[type]&.[](status)
    if category.nil?
      message = "Could not determine a category for type: #{type.inspect} and" \
        " status: #{status.inspect} on issue: #{issue_id}. If you" \
        ' specify a project: then we\'ll ask Jira for those mappings. If you\'ve done that' \
        ' and we still don\'t have the right mapping, which is possible, then use the' \
        ' "status_category_mapping" declaration in your config to manually add one.' \
        ' The mappings we do know about are below:'
      @status_category_mappings.each do |issue_type, hash|
        message << "\n  " << issue_type
        hash.each do |issue_status, issue_category|
          message << "\n    '#{issue_status}' => '#{issue_category}'"
        end
      end

      raise message
    end
    category
  end

  def load_status_category_mappings
    filename = "#{@target_path}/#{file_prefix}_statuses.json"
    # We may not always have this file. Load it if we can.
    return unless File.exist? filename

    JSON.parse(File.read(filename)).each do |type_config|
      issue_type = type_config['name']
      type_config['statuses'].each do |status_config|
        status = status_config['name']
        category = status_config['statusCategory']['name']
        (@status_category_mappings[issue_type] ||= {})[status] = category
      end
    end
  end
end
