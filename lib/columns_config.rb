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
    all_board_columns = @file_config.project_config.all_board_columns
    if board_id.nil?
      unless all_board_columns.size == 1
        message = "If the board_id isn't set then we look for all board configurations in the target" \
          ' directory. '
        if all_board_columns.empty?
          message += ' In this case, we couldn\'t find any configuration files in the target directory.'
        else
          message += 'If there is only one, we use that. In this case we found configurations for' \
            " the following board ids and this is ambiguous: #{all_board_columns}"
        end
        raise message
      end

      board_id = all_board_columns.keys[0]
    end
    board_columns = all_board_columns[board_id]

    raise "Unable to find configuration for board_id: #{board_id}" if board_columns.nil?

    board_columns.each do |column|
      date column.name, first_time_in_status(*column.status_ids)
    end
  end
end
