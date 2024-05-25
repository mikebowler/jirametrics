# frozen_string_literal: true

require 'json'

class MockFileSystem < FileSystem
  attr_reader :log_messages, :saved_json, :saved_files

  def initialize
    super
    @data = {}
    @saved_json = {}
    @saved_files = {}
    @log_messages = []
  end

  def load_json filename, fail_on_error: true
    json = @data[filename]

    return json if json
    return nil if fail_on_error == false

    raise Errno::ENOENT
  end

  def save_json filename:, json:
    @saved_json[filename] = JSON.generate(json)
  end

  def save_file filename:, content:
    @saved_files[filename] = content
  end

  def when_loading file:, json:
    @data[file] = json.clone
  end

  def log message
    # Ignore blank lines and whitespace on either end
    message = message.strip
    @log_messages << message unless message == ''
  end
end
