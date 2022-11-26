# frozen_string_literal: true

class Board
  attr_reader :backlog_statuses, :visible_columns, :raw, :possible_statuses, :sprints
  attr_accessor :cycletime, :project_config

  def initialize raw:, possible_statuses: StatusCollection.new
    @raw = raw
    @board_type = raw['type']
    @possible_statuses = possible_statuses
    @sprints = []

    columns = raw['columnConfig']['columns']

    # For a Kanban board, the first column here will always be called 'Backlog' and will NOT be
    # visible on the board. If the board is configured to have a kanban backlog then it will have
    # statuses matched to it and otherwise, there will be no statuses.
    if kanban?
      assert_jira_behaviour_true(columns[0]['name'] == 'Backlog') do
        "Expected first column to be called Backlog: #{raw}"
      end

      @backlog_statuses = statuses_from_column columns[0]
      columns = columns[1..]
    else
      # We currently don't know how to get the backlog status for a Scrum board
      @backlog_statuses = []
    end

    @visible_columns = columns.collect do |column|
      # It's possible for a column to be defined without any statuses and in this case, it won't be visible.
      BoardColumn.new column unless statuses_from_column(column).empty?
    end.compact
  end

  def statuses_from_column column
    column['statuses'].collect { |status| status['id'].to_i }
  end

  def kanban?
    @board_type == 'kanban'
  end

  def scrum?
    @board_type == 'scrum'
  end

  def id
    @raw['id'].to_i
  end

  def name
    @raw['name']
  end
end
