class ChangeItem
	attr_accessor :time, :field, :value
	attr_reader :raw

	def initialize raw: nil, time:, field: raw['field'], value: raw['toString']
		# raw will only ever be nil in a test and in that case field and value should be passed in
		@raw = raw
		@time = DateTime.parse(time)
		@field = field || @raw['field']
		@value = value || @raw['toString']
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
end