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

  def no_earlier_than date = nil
    @no_earlier_than = Date.parse(date) unless date.nil?
    @no_earlier_than
  end

  def start_date today:
    date = today.to_date - @rolling_date_count if @rolling_date_count
    date = [date, @no_earlier_than].max if date && @no_earlier_than
    date = @no_earlier_than if date.nil? && @no_earlier_than
    date
  end
end
