require 'json'
require 'date'

OUTPUT_PATH = 'target/'

class Issue
	attr_reader :changes

	def initialize raw_data
		@raw = raw_data
		@changes = []
		@raw['changelog']['histories'].each do |history|
			created = history['created']
			history['items'].each do |item|
				@changes << ChangeItem.new(raw: item, time: created)
			end
		end

		# Initial creation isn't considered a change so Jira doesn't create an entry for that
		@changes << createFakeChangeForCreation

		@changes.reverse!
	end

	def key = @raw['key']
	def type = @raw['fields']['issuetype']['name']
	def summary = @raw['fields']['summary']

	def createFakeChangeForCreation
		created_time = @raw['fields']['created']
		first_status = '--CREATED--'
		unless @changes.empty?
			first_status = @changes[-1].raw['fromString']
		end
		ChangeItem.new time: created_time, field: 'status', value: first_status
	end

	def first_time_not_in_status *args
		Date.today
	end

	def last_time_in_status *args
		Date.today
	end

	def first_time_in_status *status_names
		@changes.find { |change| change.field == 'status' && status_names.include?(change.value) }&.time
	end

	def first_time_not_in_status *status_names
		@changes.find { |change| change.field == 'status' && status_names.include?(change.value) == false }&.time
	end

	# first_status_change
	# first_time_in_status(...)
	# first_time_not_in_status(...)
	# last_time_in_status(...)
	# last_time_not_in_status(...)
	# first_time_in_status_category(...)
	# last_time_in_status_category(...)


end

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

	def to_s = "ChangeItem(field: #{field.inspect}, value: #{value().inspect}, time: '#{@time}')"
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
		issues
	end
end

if __FILE__ == $0
	Extractor.new('foo').run # do |issue, history_item|
end
