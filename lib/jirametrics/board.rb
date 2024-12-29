# frozen_string_literal: true

class Board
  attr_reader :visible_columns, :raw, :possible_statuses, :sprints, :board_type
  attr_accessor :cycletime, :project_config

  def initialize raw:, possible_statuses: # StatusCollection.new
    @raw = raw
    @board_type = raw['type']
    @possible_statuses = possible_statuses
    @sprints = []

    columns = raw['columnConfig']['columns']

    # For a Kanban board, the first column here will always be called 'Backlog' and will NOT be
    # visible on the board. If the board is configured to have a kanban backlog then it will have
    # statuses matched to it and otherwise, there will be no statuses.
    columns = columns[1..] if kanban?

    @backlog_statuses = []
    @visible_columns = columns.filter_map do |column|
      # It's possible for a column to be defined without any statuses and in this case, it won't be visible.
      BoardColumn.new column unless status_ids_from_column(column).empty?
    end
  end

  def backlog_statuses
    if @backlog_statuses.empty? && kanban?
      status_ids = status_ids_from_column raw['columnConfig']['columns'].first
      @backlog_statuses = @possible_statuses.expand_statuses(status_ids) do |unknown_status|
        # If a status is returned here that is no longer in the system then there's nothing useful
        # we can do about it. Ignore it.
      end
    end
    @backlog_statuses
  end

  def server_url_prefix
    raise "Cannot parse self: #{@raw['self'].inspect}" unless @raw['self'] =~ /^(https?:\/\/.+)\/rest\//

    $1
  end

  def url
    # Strangely, the URL isn't anywhere in the returned data so we have to fabricate it.
    "#{server_url_prefix}/secure/RapidBoard.jspa?rapidView=#{id}"
  end

  def status_ids_from_column column
    column['statuses']&.collect { |status| status['id'].to_i } || []
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
      column_names = @visible_columns.collect { |c| c.name.inspect }.join(', ')
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

  def project_id
    location = @raw['location']
    return nil unless location

    location['id'] if location['type'] == 'project'
  end

  def name
    @raw['name']
  end
end
