# frozen_string_literal: true

class ChangeItem
  attr_reader :field, :value_id, :old_value_id, :raw, :author_raw, :field_id
  attr_accessor :value, :old_value, :time

  def initialize raw:, author_raw:, time:, artificial: false
    @raw = raw
    @author_raw = author_raw
    @time = time
    raise 'ChangeItem.new() time cannot be nil' if time.nil?
    raise "Time must be an object of type Time in the correct timezone: #{@time.inspect}" unless @time.is_a? Time

    @field = @raw['field']
    @value = @raw['toString']
    @old_value = @raw['fromString']
    @value_id, @old_value_id = parse_value_ids
    @field_id = @raw['fieldId']
    @artificial = artificial
  end

  # Sprints carry a comma-separated list of ids in 'to'/'from', so those become arrays. Every other
  # field is treated as a single id: to_i grabs the leading number, or 0 for text/bracketed values like
  # Watchers or Markets (whose value_id is never used as a real id anyway).
  def parse_value_ids
    return [@raw['to']&.to_i, @raw['from']&.to_i] unless sprint?

    [parse_multiple_integer_values(@raw['to']), parse_multiple_integer_values(@raw['from'])]
  end

  # Parses a comma-separated string of integers into a list. Sprint is the only field we currently parse
  # this way, but the operation is generic - other fields may turn out to carry multiple ids too. to_s
  # turns a nil (no value) into an empty list.
  def parse_multiple_integer_values raw_value
    raw_value.to_s.split(', ').collect(&:to_i)
  end

  def author
    @author_raw&.[]('displayName') || @author_raw&.[]('name') || 'Unknown author'
  end

  def author_icon_url
    @author_raw&.[]('avatarUrls')&.[]('16x16')
  end

  def artificial? = @artificial
  def assignee? = (field == 'assignee')
  def comment? = (field == 'comment')
  def description? = (field == 'description')
  def due_date? = (field == 'duedate')
  def flagged? = (field == 'Flagged')
  def issue_type? = field == 'issuetype'
  def labels? = (field == 'labels')
  def link? = (field == 'Link')
  def priority? = (field == 'priority')
  def resolution? = (field == 'resolution')
  def sprint? = (field == 'Sprint')
  def status? = (field == 'status')
  def fix_version? = (field == 'Fix Version')

  # An alias for time so that logic accepting a Time, Date, or ChangeItem can all respond to :to_time
  def to_time = @time

  def to_s
    message = +''
    message << "ChangeItem(field: #{field.inspect}"
    message << ", value: #{value.inspect}"
    message << ':' << value_id.inspect if value_id
    if old_value
      message << ", old_value: #{old_value.inspect}"
      message << ':' << old_value_id.inspect if old_value_id
    end
    message << ", time: #{time_to_s(@time).inspect}"
    message << ", field_id: #{@field_id.inspect}" if @field_id
    message << ', artificial' if artificial?
    message << ')'
    message
  end

  def inspect = to_s

  def == other
    field.eql?(other.field) && value.eql?(other.value) && time_to_s(time).eql?(time_to_s(other.time))
  end

  def current_status_matches *status_names_or_ids
    return false unless status?

    status_names_or_ids.any? do |name_or_id|
      case name_or_id
      when Status
        name_or_id.id == @value_id
      when String
        name_or_id == @value
      else
        name_or_id == @value_id
      end
    end
  end

  def old_status_matches *status_names_or_ids
    return false unless status?

    status_names_or_ids.any? do |name_or_id|
      case name_or_id
      when Status
        name_or_id.id == @old_value_id
      when String
        name_or_id == @old_value
      else
        name_or_id == @old_value_id
      end
    end
  end

  def field_as_human_readable
    case @field
    when 'duedate' then 'Due date'
    when 'timeestimate' then 'Time estimate'
    when 'timeoriginalestimate' then 'Time original estimate'
    when 'issuetype' then 'Issue type'
    when 'IssueParentAssociation' then 'Issue parent association'
    else @field.capitalize
    end
  end

  private

  def time_to_s time
    # MRI and JRuby return different strings for to_s() so we have to explicitly provide a full
    # format so that tests work under both environments.
    time.strftime '%Y-%m-%d %H:%M:%S %z'
  end
end
