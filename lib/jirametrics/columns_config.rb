# frozen_string_literal: true

require './lib/self_or_issue_dispatcher'

class ColumnsConfig
  include SelfOrIssueDispatcher

  attr_reader :columns, :file_config

  def initialize file_config:, block:
    @columns = []
    @file_config = file_config
    @block = block
  end

  def run
    instance_eval(&@block)
  end

  def write_headers headers = nil
    @write_headers = headers unless headers.nil?
    @write_headers
  end

  def date label, proc
    @columns << [:date, label, proc]
  end

  def datetime label, proc
    @columns << [:datetime, label, proc]
  end

  def string label, proc
    @columns << [:string, label, proc]
  end

  def column_entry_times board_id: nil
    @file_config.project_config.find_board_by_id(board_id).visible_columns.each do |column|
      date column.name, first_time_in_status(*column.status_ids)
    end
  end
end
