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

    all_lines = prepare_grid

    File.open(output_filename, 'w') do |file|
      # if @columns.write_headers
      #   line = @columns.columns.collect { |_type, label, _proc| label }
      #   file.puts CSV.generate_line(line)
      # end
      # sort_output(all_lines).each do |output_line|
      all_lines.each do |output_line|
        file.puts CSV.generate_line(output_line)
      end
    end
  end

  def prepare_grid
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

    all_lines = sort_output(all_lines)

    if @columns.write_headers
      line = @columns.columns.collect { |_type, label, _proc| label }
      all_lines.insert 0, line
    end

    all_lines

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

  def file_suffix suffix = nil
    @file_suffix = suffix unless suffix.nil?
    @file_suffix
  end
end
