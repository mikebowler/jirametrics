# frozen_string_literal: true

require 'json'

class MockFileSystem < FileSystem
  attr_reader :log_messages, :saved_json, :saved_files

  def initialize
    super
    @data = {}
    @foreach_data = {}
    @saved_json = {}
    @saved_files = {}
    @log_messages = []
  end

  def load_json filename, fail_on_error: true
    json = @data[filename]

    return super if json == :not_mocked
    return json if json
    return nil if fail_on_error == false

    raise Errno::ENOENT, filename
  end

  def save_json filename:, json:
    @saved_json[filename] = JSON.generate(json)
  end

  def save_file filename:, content:
    @saved_files[filename] = content
  end

  def when_loading file:, json:
    raise "File must be a string or :not_mocked. Found #{file.inspect}" unless file.is_a?(String) || file == :not_mocked

    @data[file] = json.clone
  end

  # iterating

  def when_foreach root:, result:
    @foreach_data[root] = result
  end

  def foreach root
    results = @foreach_data[root]
    raise "foreach called on directory #{root.inspect} but nothing set in the mock" unless results

    results.each { |file| yield file } # rubocop:disable Style/ExplicitBlockArgument
  end

  def log message, also_write_to_stderr: false # rubocop:disable Lint/UnusedMethodArgument
    # Ignore blank lines and whitespace on either end
    message = message.strip
    @log_messages << message unless message == ''
  end
end
