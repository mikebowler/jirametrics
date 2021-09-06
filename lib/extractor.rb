require 'json'
require 'date'

OUTPUT_PATH = 'target/'

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
