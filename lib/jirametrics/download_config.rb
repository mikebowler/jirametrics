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

  def project_key _key = nil
    raise 'project, filter, and jql directives are no longer supported. See ' \
      'https://github.com/mikebowler/jira-export/wiki/Deprecated#project-filter-and-jql-are-no-longer-supported-in-the-download-section'
  end

  def board_ids *ids
    deprecated message: 'board_ids in the download block are deprecated. See https://github.com/mikebowler/jira-export/wiki/Deprecated'
    @board_ids = ids unless ids.empty?
    @board_ids
  end

  def filter_name _filter = nil
    project_key
  end

  def jql _query = nil
    project_key
  end

  def rolling_date_count count = nil
    @rolling_date_count = count unless count.nil?
    @rolling_date_count
  end
end
