# frozen_string_literal: true

require 'json'

class MockJsonFileLoader
  def initialize
    @data = {}
  end

  def load filename, fail_on_error: true
    puts "\n#{self.class}(#{filename})"
    json = @data[filename]

    return json if json
    return nil if fail_on_error == false

    raise Errno::ENOENT
  end

  def when file:, json:
    @data[file] = json.clone
  end
end
