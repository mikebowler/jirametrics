# frozen_string_literal: true

class ChangeItem
  attr_reader :field, :value_id, :old_value_id, :raw, :author, :time
  attr_accessor :value, :old_value

  def initialize raw:, time:, author:, artificial: false
    @raw = raw
    @time = time
    raise 'ChangeItem.new() time cannot be nil' if time.nil?
    raise "Time must be an object of type Time in the correct timezone: #{@time.inspect}" unless @time.is_a? Time

    @field = @raw['field']
    @value = @raw['toString']
    @value_id = @raw['to'].to_i
    @old_value = @raw['fromString']
    @old_value_id = @raw['from']&.to_i
    @artificial = artificial
    @author = author
  end

  def status? = (field == 'status')

  def flagged? = (field == 'Flagged')

  def priority? = (field == 'priority')

  def resolution? = (field == 'resolution')

  def artificial? = @artificial

  def sprint? = (field == 'Sprint')

  def link? = (field == 'Link')

  def labels? = (field == 'labels')

  # An alias for time so that logic accepting a Time, Date, or ChangeItem can all respond to :to_time
  def to_time = @time

  def to_s
    message = +''
    message << "ChangeItem(field: #{field.inspect}"
    message << ", value: #{value.inspect}"
    message << ':' << value_id.inspect if status?
    if old_value
      message << ", old_value: #{old_value.inspect}"
      message << ':' << old_value_id.inspect if status?
    end
    message << ", time: #{time_to_s(@time).inspect}"
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

  private

  def time_to_s time
    # MRI and JRuby return different strings for to_s() so we have to explicitly provide a full
    # format so that tests work under both environments.
    time.strftime '%Y-%m-%d %H:%M:%S %z'
  end
end
