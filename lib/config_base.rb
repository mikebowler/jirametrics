require 'csv'
require 'date'

# The goal was to make both the configuration itself and the issue/loader
# objects easy to read so the tricky (specifically meta programming) parts 
# are all in here. Be cautious when changing this file.
class ConfigBase
  attr_reader :issues, :file_prefix, :jql, :project_key, :status_category_mappings, :jira_config
  attr_reader :board_id, :board_columns

  @@target_path = 'target/'
  @@configs = []
  @@jira_config = 'jira_config.json'

  def self.project file_prefix:, project: nil, filter: nil, jql: nil, board_id: nil, &block
    instance = new(
      file_prefix: file_prefix, 
      project: project, 
      filter: filter, 
      jql: jql, 
      board_id: board_id, 
      export_config_block: block
    )
    @@configs << instance
  end

  # Does nothing. An easy way to comment out a project
  def self.xproject *args
  end

  def self.target_path(path) = @@target_path = path
  def self.jira_config(file_prefix) = @@jira_config = file_prefix
  def self.instances = @@configs

  def initialize file_prefix:, project: nil, filter: nil, jql: nil, rolling_date_count: nil, board_id: nil, export_config_block: nil
    @file_prefix = file_prefix
    @csv_filename = "#{@@target_path}/#{file_prefix}.csv"
    @export_config_block = export_config_block
    @jql = make_jql project: project, filter: filter, jql: jql, rolling_date_count: rolling_date_count
    @project_key = project
    @status_category_mappings = {}
    @jira_config = @@jira_config
    @board_id = board_id
  end

  def make_jql project: nil, filter: nil, jql: nil, rolling_date_count: nil, today: Date.today
    segments = []
    segments << "project=#{project.inspect}" unless project.nil?
    segments << "filter=#{filter.inspect}" unless filter.nil?
    unless rolling_date_count.nil?
      start_date = today - rolling_date_count
      segments << %(status changed DURING ("#{start_date.strftime '%Y-%m-%d'} 00:00","#{today.strftime '%Y-%m-%d'}")) 
    end
    segments << jql unless jql.nil?
    raise "Everything was nil" if segments.empty?
    segments.join ' AND '
  end

  def columns write_headers: true, &block
    @export_columns = ExportColumns.new self
    @export_columns.instance_eval &block
    @write_headers = write_headers
  end

  def load_all_issues file_prefix:, target_path:
    issues = []
    Dir.foreach(target_path) do |filename|
      if filename =~ /#{file_prefix}_\d+\.json/
        content = JSON.parse File.read("#{target_path}#{filename}")
        content['issues'].each { |issue| issues << Issue.new(issue) }
      end
    end
    issues
  end

  def run
    load_status_category_mappings
    load_board_configuration

    @issues = load_all_issues file_prefix: @file_prefix, target_path: @@target_path
    self.instance_eval &@export_config_block

    all_lines = @issues.collect do |issue|
      line = []
      @export_columns.columns.each do |type, name, block|
        # Invoke the block that will retrieve the result from Issue
        result = instance_exec(issue, &block)
        # Convert that result to the appropriate type
        line << __send__(:"to_#{type}", result)
      end
      line
    end

    File.open(@csv_filename, 'w') do |file|
      if @write_headers
        line = @export_columns.columns.collect { |type, label, proc| label }
        file.puts CSV.generate_line(line)
      end
      sort_output(all_lines).each do |line|
        file.puts CSV.generate_line(line)
      end
    end

  end

  # We'll probably make sorting configurable at some point but for now it's hard coded for our
  # most common usecase - the Team Dashboard from FocusedObjective.com. The rule for that one 
  # is that all empty values in the first column should be at the bottom.
  def sort_output all_lines
    all_lines.sort do |a, b| 
      if a[0].nil?
        1
      elsif b[0].nil?
        -1
      else
        a[0] <=> b[0]
      end
    end
  end

  def load_status_category_mappings
    filename = "#{@@target_path}/#{file_prefix}_statuses.json"
    if File.exists? filename
      JSON.parse(File.read(filename)).each do |type_config|
        issue_type = type_config['name'] 
        @status_category_mappings[issue_type] = {}
        type_config['statuses'].each do |status_config|
          status = status_config['name']
          category = status_config['statusCategory']['name']
          @status_category_mappings[issue_type][status] = category
        end
      end
    end
    raise "categories file not found" unless File.exists? filename
  end

  def load_board_configuration
    filename = "#{@@target_path}/#{file_prefix}_board_configuration.json"
    if File.exists? filename
      json = JSON.parse(File.read(filename))
      @board_columns = json['columnConfig']['columns'].collect do |column|
        BoardColumn.new column
      end
    end
  end

  def category_for type:, status:, issue_id:
    category = @status_category_mappings[type]&.[](status)
    if category.nil?
      message = "Could not determine a category for type: #{type.inspect} and " \
        " status: #{status.inspect} on issue: #{issue_id}. If you" \
        " specify a project: then we'll ask Jira for those mappings. If you've done that " \
        " and we still don't have the right mapping, which is possible, then use the " \
        " 'status_category_mapping' declaration in your config to manually add one." \
        " The mappings we do know about are below:"
      @status_category_mappings.each do |type, hash|
        message << "\n  " << type
        hash.each do |status, category|
          message << "\n    '#{status}'' => '#{category}'"
        end
      end

      raise message
    end
    category
  end

  # TODO: to_date needs to know which timezone we're converting to.
  def to_date object
    object&.to_date
  end

  def to_string object
    object.to_s
  end

  def status_category_mapping type:, status:, category:
    mappings = self.status_category_mappings
    mappings[type] = {} unless mappings[type]
    mappings[type][status] = category
  end

end