# frozen_string_literal: true

class DownloadConfig
  attr_reader :project_config
  attr_writer :jql

  def initialize project_config:, block:
    @project_config = project_config
    @block = block
  end

  def run
    puts @block.inspect
    instance_eval(&@block)
  end

  def jql today: Date.today
    return @jql if @jql

    segments = []
    segments << "project=#{@project_key.inspect}" unless @project_key.nil?
    segments << "filter=#{@filter_name.inspect}" unless @filter_name.nil?
    unless @rolling_date_count.nil?
      start_date = today - @rolling_date_count
      status_changed_jql = %(status changed DURING ("#{start_date.strftime '%Y-%m-%d'} 00:00","#{today.strftime '%Y-%m-%d'}"))
      segments << %(((status changed AND resolved = null) OR (#{status_changed_jql})))
    end
    segments << @jql unless @jql.nil?
    return segments.join ' AND ' unless segments.empty?

    raise 'Everything was nil'
  end

  def project_key *arg
    @project_key = arg[0] unless arg.empty?
    @project_key
  end

  def board_id *arg
    @board_id = arg[0] unless arg.empty?
    @board_id
  end

  def filter_name *arg
    @filter_name = arg[0] unless arg.empty?
    @filter_name
  end

  def rolling_date_count *arg
    @rolling_date_count = arg[0] unless arg.empty?
    @rolling_date_count
  end
end
