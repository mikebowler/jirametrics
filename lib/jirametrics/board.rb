# frozen_string_literal: true

class Board
  attr_reader :visible_columns, :raw, :possible_statuses, :sprints
  attr_accessor :cycletime, :project_config

  def initialize raw:, possible_statuses:, features: []
    @raw = raw
    @possible_statuses = possible_statuses
    @sprints = []
    @features = features

    columns = raw['columnConfig']['columns']
    ensure_uniqueness_of_column_names! columns

    # For a classic Kanban board (type 'kanban'), the first column will always be called 'Backlog'
    # and will NOT be visible on the board. This does not apply to team-managed boards (type 'simple').
    columns = columns.drop(1) if board_type == 'kanban'

    @backlog_statuses = []
    @visible_columns = columns.filter_map do |column|
      # It's possible for a column to be defined without any statuses and in this case, it won't be visible.
      BoardColumn.new column unless status_ids_from_column(column).empty?
    end
  end

  def backlog_statuses
    if @backlog_statuses.empty? && board_type == 'kanban'
      status_ids = status_ids_from_column raw['columnConfig']['columns'].first
      @backlog_statuses = status_ids.filter_map do |id|
        @possible_statuses.find_by_id id
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

  def board_type = raw['type']

  def scrum?
    return true if board_type == 'scrum'
    return false unless board_type == 'simple'

    has_sprints_feature?
  end

  def kanban?
    return true if board_type == 'kanban'
    return false unless board_type == 'simple'

    !scrum?
  end

  def team_managed_kanban?
    board_type == 'simple' && !has_sprints_feature?
  end

  def has_sprints_feature?
    @features.any? { |f| f.name == 'jsw.agility.sprints' && f.enabled? }
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

  def accumulated_status_ids_per_column
    accumulated_status_ids = []
    visible_columns.reverse.filter_map do |column|
      next if column == @fake_column

      accumulated_status_ids += column.status_ids
      [column.name, accumulated_status_ids.dup]
    end.reverse
  end

  def ensure_uniqueness_of_column_names! json
    all_names = []
    json.each do |column_json|
      name = column_json['name']
      if all_names.include? name
        (2..).each do |i|
          new_name = "#{name}-#{i}"
          next if all_names.include?(new_name)

          name = new_name
          column_json['name'] = new_name
          break
        end
      end
      all_names << name
    end
  end

  def estimation_configuration
    EstimationConfiguration.new raw: raw['estimation']
  end

  def inspect
    "Board(id: #{id}, name: #{name.inspect}, board_type: #{board_type.inspect})"
  end
end
