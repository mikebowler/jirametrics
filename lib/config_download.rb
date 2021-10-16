# frozen_string_literal: true

class ConfigDownload
  def initialize exporter, block
    @exporter = exporter
    @block = block
  end
end