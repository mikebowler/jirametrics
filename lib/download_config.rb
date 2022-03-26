# frozen_string_literal: true

require 'date'

class DownloadConfig
  attr_reader :project_config #, :date_range

  def initialize project_config:, block:
    @project_config = project_config
    @block = block
    @board_ids = []
  end

  def run
    instance_eval(&@block)
  end

  def project_key key = nil
    @project_key = key unless key.nil?
    @project_key
  end

  def board_ids *ids
    @board_ids = ids unless ids.empty?
    @board_ids
  end

  def filter_name filter = nil
    @filter_name = filter unless filter.nil?
    @filter_name
  end

  def rolling_date_count count = nil
    @rolling_date_count = count unless count.nil?
    @rolling_date_count
  end
end
