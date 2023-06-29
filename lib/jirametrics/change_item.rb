# frozen_string_literal: true

class ChangeItem
  attr_reader :field, :value_id, :old_value_id, :raw, :author
  attr_accessor :value, :old_value, :time

  def initialize raw:, time:, author:, artificial: false
    # raw will only ever be nil in a test and in that case field and value should be passed in
    @raw = raw
    @time = time
    raise "Time must be an object of type Time in the correct timezone: #{@time}" if @time.is_a? String

    @field = field || @raw['field']
    @value = value || @raw['toString']
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

  def story_points? = (field == 'Story Points')

  def link? = (field == 'Link')

  def to_s
    message = "ChangeItem(field: #{field.inspect}, value: #{value.inspect}, time: \"#{@time}\""
    message += ', artificial' if artificial?
    message += ')'
    message
  end

  def inspect = to_s

  def == other
    field.eql?(other.field) && value.eql?(other.value) && time.to_s.eql?(other.time.to_s)
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
end
