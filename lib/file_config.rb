# frozen_string_literal: true

require 'csv'

class FileConfig
  attr_reader :project_config

  def initialize project_config:, block:
    @project_config = project_config
    @block = block
    @columns = nil
  end

  def run
    instance_eval(&@block)
    @columns.run

    all_lines = issues.collect do |issue|
      line = []
      @columns.columns.each do |type, _name, block|
        # Invoke the block that will retrieve the result from Issue
        result = instance_exec(issue, &block)
        # Convert that result to the appropriate type
        line << __send__(:"to_#{type}", result)
      end
      line
    end

    File.open(output_filename, 'w') do |file|
      if @columns.write_headers
        line = @columns.columns.collect { |_type, label, _proc| label }
        file.puts CSV.generate_line(line)
      end
      sort_output(all_lines).each do |output_line|
        file.puts CSV.generate_line(output_line)
      end
    end
  end

  def output_filename
    segments = []
    segments << project_config.target_path
    segments << project_config.file_prefix
    segments << (@file_suffix || '.csv')
    segments.join
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

  def issues
    unless @issues
      issues = []
      Dir.foreach(@project_config.target_path) do |filename|
        if filename =~ /#{@project_config.file_prefix}_\d+\.json/
          content = JSON.parse File.read("#{@project_config.target_path}#{filename}")
          content['issues'].each { |issue| issues << Issue.new(issue) }
        end
      end
      @issues = issues
    end

    @issues
  end

  def columns &block
    raise 'Can only have one columns declaration inside a file' if @column

    @columns = ColumnsConfig.new file_config: self, block: block
  end

  # TODO: to_date needs to know which timezone we're converting to.
  def to_date object
    object&.to_date
  end

  def to_string object
    object.to_s
  end

  def file_suffix *arg
    @file_suffix = arg[0] unless arg.empty?
    @file_suffix
  end

  def category_for type:, status:, issue_id:
    category = project.status_category_mappings[type]&.[](status)
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
          message << "\n    '#{issue_status}'' => '#{issue_category}'"
        end
      end

      raise message
    end
    category
  end

end
