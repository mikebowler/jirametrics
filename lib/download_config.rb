# frozen_string_literal: true

require 'date'

class DownloadConfig
  attr_reader :project_config, :date_range
  attr_writer :jql

  def initialize project_config:, block:
    @project_config = project_config
    @block = block
    @board_ids = []
  end

  def run
    instance_eval(&@block)
  end

  def jql today: Date.today
    return @jql if @jql

    segments = []
    segments << "project=#{@project_key.inspect}" unless @project_key.nil?
    segments << "filter=#{@filter_name.inspect}" unless @filter_name.nil?
    unless @rolling_date_count.nil?
      start_date = today - @rolling_date_count
      @date_range = (start_date..today)

      status_changed_jql =
        %(status changed DURING ("#{start_date.strftime '%Y-%m-%d'} 00:00","#{today.strftime '%Y-%m-%d'} 23:59"))
      segments << %(((status changed AND resolved = null) OR (#{status_changed_jql})))
    end
    segments << @jql unless @jql.nil?
    return segments.join ' AND ' unless segments.empty?

    raise 'Everything was nil'
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
