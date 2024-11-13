# frozen_string_literal: true

require 'json'

class FileSystem
  attr_accessor :logfile, :logfile_name

  # Effectively the same as File.read except it forces the encoding to UTF-8
  def load filename, supress_deprecation: false
    # deprecated message: 'call load_json instead', date: '2024-11-13' if filename.end_with? '.json'
    raise 'call load_json instead' if filename.end_with?('.json') && !supress_deprecation

    File.read filename, encoding: 'UTF-8'
  end

  def load_json filename, fail_on_error: true
    return nil if fail_on_error == false && File.exist?(filename) == false

    JSON.parse load(filename, supress_deprecation: true)
  end

  def save_json json:, filename:
    save_file content: JSON.pretty_generate(compress json), filename: filename
  end

  def save_file content:, filename:
    file_path = File.dirname(filename)
    FileUtils.mkdir_p file_path unless File.exist?(file_path)

    File.write(filename, content)
  end

  def log message, also_write_to_stderr: false
    logfile.puts message
    $stderr.puts message if also_write_to_stderr # rubocop:disable Style/StderrPuts
  end

  # In some Jira instances, a sizeable portion of the JSON is made up of empty fields. I've seen
  # cases where this simple compression will drop the filesize by half.
  def compress node
    if node.is_a? Hash
      node.reject! { |_key, value| value.nil? || (value.is_a?(Array) && value.empty?) }
      node.each_value { |value| compress value }
    elsif node.is_a? Array
      node.each { |a| compress a }
    end
    node
  end

  def foreach root, &block
    Dir.foreach root, &block
  end
end
