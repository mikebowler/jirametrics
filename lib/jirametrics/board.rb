# frozen_string_literal: true

class Board
  attr_reader :visible_columns, :raw, :possible_statuses, :sprints, :backlog_statuses
  attr_accessor :cycletime, :project_config, :expedited_priority_names

  def initialize raw:, possible_statuses: StatusCollection.new
    @raw = raw
    @board_type = raw['type']
    @possible_statuses = possible_statuses
    @sprints = []
    @expedited_priority_names = []

    columns = raw['columnConfig']['columns']

    # For a Kanban board, the first column here will always be called 'Backlog' and will NOT be
    # visible on the board. If the board is configured to have a kanban backlog then it will have
    # statuses matched to it and otherwise, there will be no statuses.
    if kanban?
      assert_jira_behaviour_true(columns[0]['name'] == 'Backlog') do
        "Expected first column to be called Backlog: #{raw}"
      end

      @backlog_statuses = @possible_statuses.expand_statuses(status_ids_from_column columns[0]) do |unknown_status|
        # Yet another "theoretically impossible and yet we've seen it in production" moment
        puts "Status #{unknown_status.inspect} is defined as being in the backlog for board #{name.inspect}:#{id} " \
          'and yet it\'s not defined in the list of possible statuses available to the project. Check your Jira ' \
          'configuration'
      end
      columns = columns[1..]
    else
      # We currently don't know how to get the backlog status for a Scrum board
      @backlog_statuses = []
    end

    @visible_columns = columns.collect do |column|
      # It's possible for a column to be defined without any statuses and in this case, it won't be visible.
      BoardColumn.new column unless status_ids_from_column(column).empty?
    end.compact
  end

  def url
    # Strangely, the URL isn't anywhere in the returned data so we have to fabricate it.
    raise "Cannot parse self: #{@raw['self']}" unless @raw['self'] =~ /^(https?:\/\/[^\/]+)\//

    "#{$1}/secure/RapidBoard.jspa?rapidView=#{id}"
  end

  def status_ids_from_column column
    column['statuses'].collect { |status| status['id'].to_i }
  end

  def status_ids_in_or_right_of_column column_name
    status_ids = []
    found_it = false

    @visible_columns.each do |column|
      # Check both the current name and also the original raw name in case anonymization has happened.
      found_it = true if column.name == column_name || column.raw['name'] == column_name
      status_ids += column.status_ids if found_it
    end

    unless found_it
      column_names = @visible_columns.collect(&:name).collect(&:inspect).join(', ')
      raise "No visible column with name: #{column_name.inspect} Possible options are: #{column_names}"
    end
    status_ids
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
