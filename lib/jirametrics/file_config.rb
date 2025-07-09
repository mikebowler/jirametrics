# frozen_string_literal: true

require 'csv'

class FileConfig
  attr_reader :project_config, :issues

  def initialize project_config:, block:, today: Date.today
    @project_config = project_config
    @block = block
    @columns = nil
    @today = today
  end

  def run
    @issues = project_config.issues
    instance_eval(&@block)

    if @columns
      all_lines = prepare_grid

      content = all_lines.collect { |line| CSV.generate_line line }.join
      project_config.exporter.file_system.save_file content: content, filename: output_filename
    elsif @html_report
      @html_report.run
    else
      raise 'Must specify one of "columns" or "html_report"'
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

    all_lines = all_lines.select(&@only_use_row_if) if @only_use_row_if
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
    segments << project_config.get_file_prefix
    segments << (@file_suffix || "-#{@today}.csv")
    segments.join
  end

  # We'll probably make sorting configurable at some point but for now it's hard coded for our
  # most common usecase - the Team Dashboard from FocusedObjective.com. The rule for that one
  # is that all empty values in the first column should be at the bottom.
  def sort_output all_lines
    all_lines.sort do |a, b|
      result = nil
      if a[0] == b[0]
        result = a[1..] <=> b[1..]
      elsif a[0].nil?
        result = 1
      elsif b[0].nil?
        result = -1
      else
        result = a[0] <=> b[0]
      end

      # This will only happen if one of the objects isn't comparable. Seen in production.
      result = -1 if result.nil?
      result
    end
  end

  def columns &block
    assert_only_one_filetype_config_set
    @columns = ColumnsConfig.new file_config: self, block: block
  end

  def html_report &block
    assert_only_one_filetype_config_set
    if block.nil?
      project_config.file_system.warning 'No charts were specified for the report. This is almost certainly a mistake.'
      block = ->(_) {}
    end

    @html_report = HtmlReportConfig.new file_config: self, block: block
  end

  def assert_only_one_filetype_config_set
    raise 'Can only have one columns or html_report declaration inside a file' if @columns || @html_report
  end

  def only_use_row_if &block
    @only_use_row_if = block
  end

  def to_date object
    to_datetime(object)&.to_date
  end

  def to_datetime object
    return nil if object.nil?

    object = object.to_time.to_datetime
    object = object.new_offset(@timezone_offset) if @timezone_offset
    object
  end

  def to_string object
    object.to_s
  end

  def to_integer object
    object.to_i
  end

  def file_suffix suffix = nil
    @file_suffix = suffix unless suffix.nil?
    @file_suffix
  end

  def children
    result = []
    result << @columns if @columns
    result << @html_report if @html_report
    result
  end
end
