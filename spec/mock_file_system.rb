# frozen_string_literal: true

require 'json'

class MockFileSystem
  attr_reader :log_messages

  def initialize
    super
    @data = {}
    @log_messages = []
  end

  def load_json filename, fail_on_error: true
    puts "\n#{self.class}(#{filename})"
    json = @data[filename]

    return json if json
    return nil if fail_on_error == false

    raise Errno::ENOENT
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
