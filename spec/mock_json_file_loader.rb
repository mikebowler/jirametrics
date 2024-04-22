# frozen_string_literal: true

require 'json'

class MockFileSystem
  def initialize
    @data = {}
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
end
