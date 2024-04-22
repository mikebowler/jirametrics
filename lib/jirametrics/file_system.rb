# frozen_string_literal: true

require 'json'

class FileSystem
  attr_accessor :logfile, :logfile_name

  def load_json filename, fail_on_error: true
    return nil if fail_on_error == false && File.exist?(filename) == false

    JSON.parse File.read(filename)
  end

  def save_json json:, filename:
    file_path = File.dirname(filename)
    FileUtils.mkdir_p file_path unless File.exist?(file_path)

    File.write(filename, JSON.pretty_generate(compress json))
  end

  def log message
    logfile.puts message
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
end
