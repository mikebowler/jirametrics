require 'json'
require 'date'

class Extractor
	def initialize file_prefix, target_path
		@file_prefix = file_prefix
		@target_path = target_path
	end

	def run
		issues = []
		Dir.foreach(@target_path) do |filename|
			if filename =~ /#{@file_prefix}_\d+\.json/
				content = JSON.parse File.read("#{@target_path}#{filename}")
				content['issues'].each { |issue| issues << Issue.new(issue) }
			end
		end
		issues
	end
end

if __FILE__ == $0
	Extractor.new('foo').run # do |issue, history_item|
end
