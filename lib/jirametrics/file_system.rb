# frozen_string_literal: true

require 'json'

class FileSystem
  def load_json filename, fail_on_error: true
    return nil if fail_on_error == false && File.exist?(filename) == false

    JSON.parse File.read(filename)
  end
end
