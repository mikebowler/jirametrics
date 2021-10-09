class ChangeItem
  attr_reader :time, :field, :value, :value_id, :old_value, :old_value_id
  attr_reader :raw

  def initialize raw:, time: #, field: raw['field'], value: raw['toString']
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

  def to_s = "ChangeItem(field: #{field.inspect}, value: #{value().inspect}, time: '#{@time}')"
  def inspect = to_s

  def == other
    field.eql?(other.field) && value.eql?(other.value) && time.to_s.eql?(other.time.to_s)
  end

  def matches_status status_names_or_ids
    return false unless status?

    status_names_or_ids.each do |name_or_id|
      return true if @value == name_or_id || @value_id == name_or_id
    end
    return false
  end
end