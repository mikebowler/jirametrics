require 'json'
require 'date'

OUTPUT_PATH = 'target/'

class Issue
	attr_reader :changes

	def initialize raw_data
		@raw = raw_data
		@changes = []
		@raw['changelog']['histories'].each do |history|
			created_at = DateTime.parse history['created']
			history['items'].each do |item|
				@changes << ChangeItem.new(raw: item, time: created_at)
			end
		end
		@changes.reverse!
	end

	def key
		@raw['key']
	end
end

class ChangeItem
	attr_accessor :time, :field, :value
	attr_reader :raw

	def initialize raw: nil, time:, field: raw['field'], value: raw['toString']
		# raw will only ever be nil in a test and in that case field and value should be passed in
		@raw = raw
		@time = time
		@field = field || @raw['field']
		@value = value || @raw['toString']
	end

	# This is the new 'endless' method syntax in ruby 3. Still undecided if I like it.
	def status?   = (field == 'status')
	def flagged?  = (field == 'Flagged')
	def priority? = (field == 'priority')

	def to_s = "ChangeItem(field: #{field.inspect}, value: #{value().inspect}, time: '#{@created_at.to_s}')"
	def inspect = to_s

	def == other
		field.eql?(other.field) && value.eql?(other.value) && time.to_s.eql?(other.time.to_s)
	end
end

class Extractor
	def initialize file_prefix
		@file_prefix = file_prefix
	end

	def run
		issues = []
		Dir.foreach(OUTPUT_PATH) do |filename|
			if filename =~ /#{@file_prefix}_\d+\.json/
				content = JSON.parse File.read("#{OUTPUT_PATH}#{filename}")
				content['issues'].each { |issue| issues << Issue.new(issue) }
			end
		end
	end
end

if __FILE__ == $0
	Extractor.new('foo').run # do |issue, history_item|
end
