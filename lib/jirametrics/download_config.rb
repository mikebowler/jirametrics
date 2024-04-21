# frozen_string_literal: true

require 'date'

class DownloadConfig
  attr_reader :project_config

  def initialize project_config:, block:
    @project_config = project_config
    @block = block
    @board_ids = []
  end

  def run
    instance_eval(&@block)
  end

  def rolling_date_count count = nil
    @rolling_date_count = count unless count.nil?
    @rolling_date_count
  end
end
