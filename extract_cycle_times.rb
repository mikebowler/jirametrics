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
				@changes << ChangeItem.new(item, created_at)
			end
		end
	end

	def key
		@raw['key']
	end
end

class ChangeItem
	attr_reader :created_at
	def initialize raw, created_at
		@raw = raw
		@created_at = created_at
	end

	# This is the new 'endless' method syntax in ruby 3. Still undecided if I like it.
	def field     = @raw['field']
	def value     = @raw['toString']

	def status?   = (field == 'status')
	def flagged?  = (field == 'Flagged')
	def priority? = (field == 'priority')

	def to_s = "ChangeItem(field=#{field()}, value=#{value()} time=#{@created_at})"

	def equal?(other) = self == other
	def eql?(other) = self == other

	def == other
		field.eql?(other.field) && value.eql?(other.value) && created_at.to_s.eql?(other.created_at.to_s)
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
