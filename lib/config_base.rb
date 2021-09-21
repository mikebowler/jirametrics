require 'csv'

# The goal was to make both the configuration itself and the issue/loader
# objects easy to read so the tricky (specifically meta programming) parts 
# are all in here. Be cautious when changing this file.
class ConfigBase
	class ExportColumns < BasicObject
		attr_reader :columns
		def initialize = @columns = []

		def date label, block
			@columns << [:date, label, block]
		end

		def string label, block
			@columns << [:string, label, block]
		end

		def method_missing method_name, *args, &block
			-> (issue) { issue.__send__ method_name, *args }
		end
	end

	attr_reader :issues, :file_prefix, :jql, :project_key
	@@target_path = 'target/'
	@@configs = []

	def self.export file_prefix:, project: nil, filter: nil, jql: nil, &block
		instance = ConfigBase.new(
			file_prefix: file_prefix, project: project, filter: filter, jql: jql, export_config_block: block
		)
		@@configs << instance
	end

	# Does nothing. An easy way to comment out a project
	def self.xexport *args
	end

	def self.target_path(path) = @@target_path = path
	def self.instances = @@configs

	def initialize file_prefix:, project: nil, filter: nil, jql: nil, export_config_block: nil
		@file_prefix = file_prefix
		@csv_filename = "#{@@target_path}/#{file_prefix}.csv"
		@export_config_block = export_config_block
		@jql = make_jql project: project, filter: filter, jql: jql
		@project_key = project
	end

	def make_jql project:, filter:, jql:
		return jql unless jql.nil?
		return "project=#{project.inspect}" unless project.nil?
		return "filter=#{filter.inspect}" unless filter.nil?
		raise "Everything was nil"
	end

	def columns write_headers: true, &block
		@export_columns = ExportColumns.new
		@export_columns.instance_eval &block
		@write_headers = write_headers
	end

	def run
		@issues = Extractor.new(@file_prefix, @@target_path).run
		self.instance_eval &@export_config_block

		File.open(@csv_filename, 'w') do |file|
			if @write_headers
				line = @export_columns.columns.collect { |type, label, proc| label }
				file.puts CSV.generate_line(line)
			end
			@issues.each do |issue|
				line = []
				@export_columns.columns.each do |type, name, block|
					# Invoke the block that will retrieve the result from Issue
					result = instance_exec(issue, &block)
					# Convert that result to the appropriate type
					line << __send__(:"to_#{type}", result)
				end
				file.puts CSV.generate_line(line)
			end
		end
	end

	# TODO: to_date needs to know which timezone we're converting to.
	def to_date object
		object&.to_date
	end

	def to_string object
		object.to_s
	end

end