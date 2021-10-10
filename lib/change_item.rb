# frozen_string_literal: true

class ChangeItem
  attr_reader :time, :field, :value, :value_id, :old_value, :old_value_id, :raw

  def initialize raw:, time:
    # raw will only ever be nil in a test and in that case field and value should be passed in
    @raw = raw
    @time = DateTime.parse(time)
    @field = field || @raw['field']
    @value = value || @raw['toString']
    @value_id = @raw['to'].to_i
    @old_value = @raw['fromString']
    @old_value_id = @raw['from']&.to_i
  end

  def status?   = (field == 'status')

  def flagged?  = (field == 'Flagged')

  def priority? = (field == 'priority')

  def resolution? = (field == 'resolution')

  def to_s
    "ChangeItem(field: #{field.inspect}, value: #{value.inspect}, time: '#{@time}')"
  end

  def inspect = to_s

  def == other
    field.eql?(other.field) && value.eql?(other.value) && time.to_s.eql?(other.time.to_s)
  end

  def matches_status status_names_or_ids
    return false unless status?

    status_names_or_ids.any? do |name_or_id|
      @value == name_or_id || @value_id == name_or_id # rubocop:disable Style/MultipleComparison
    end
  end
end
