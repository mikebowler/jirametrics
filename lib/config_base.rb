require 'csv'

class ExportColumns < BasicObject
    attr_reader :columns

    def initialize config
        @columns = []
        @config = config
    end

    def date label, block
        @columns << [:date, label, block]
    end

    def string label, block
        @columns << [:string, label, block]
    end

    # Why is this here? Because I keep forgetting that puts() will be caught by method_missing and
    # that makes me spin through a debug cycle. So I make it do the expected thing.
    def puts *args
        $stdout.puts *args
    end

    def method_missing method_name, *args, &block
        # Have to reference config outside the lambda so that it's accessible inside.
        # When the lambda is executed for real, it will be running inside the context of an Issue
        # object and at that point @config won't be referencing a variable from the right object.
        config = @config

        -> (issue) do
            parameters = issue.method(method_name.to_sym).parameters
            # Is the first parameter called config?
            if parameters.empty? == false && parameters[0][1] == :config
                new_args = [config] + args
                issue.__send__ method_name, *new_args
            else
                issue.__send__ method_name, *args 
            end
        end # *([config] + args) }
    end
end

# The goal was to make both the configuration itself and the issue/loader
# objects easy to read so the tricky (specifically meta programming) parts 
# are all in here. Be cautious when changing this file.
class ConfigBase
    attr_reader :issues, :file_prefix, :jql, :project_key, :status_category_mappings
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
        @export_columns = ExportColumns.new self
        @export_columns.instance_eval &block
        @write_headers = write_headers
    end

    def run
        load_status_category_mappings

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

    def load_status_category_mappings
        filename = "#{@@target_path}/#{file_prefix}_statuses.json"
        @status_category_mappings = {}

        if File.exists? filename
            JSON.parse(File.read(filename)).each do |type_config|
                issue_type = type_config['name'] # Epic
                type_config['statuses'].each do |status_config|
                    status = status_config['name'] # Discovering
                    category = status_config['statusCategory']['name'] # To Do

                    @status_category_mappings[issue_type] = [status, category]
                end
            end
        end
        raise "categories file not found" unless File.exists? filename

    end

    # TODO: to_date needs to know which timezone we're converting to.
    def to_date object
        object&.to_date
    end

    def to_string object
        object.to_s
    end

end