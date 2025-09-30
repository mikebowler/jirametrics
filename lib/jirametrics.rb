# frozen_string_literal: true

require 'thor'
require 'require_all'

# This one does need to be loaded early. The rest will be loaded later.
require 'jirametrics/file_system'

class JiraMetrics < Thor
  def self.exit_on_failure?
    true
  end

  map %w[--version -v] => :__print_version

  desc '--version, -v', 'print the version'
  def __print_version
    puts Gem.loaded_specs['jirametrics'].version
  end

  option :config
  option :name
  desc 'export', "Export data into either reports or CSV's as per the configuration"
  def export
    load_config options[:config]
    Exporter.instance.export(name_filter: options[:name] || '*')
  end

  option :config
  option :name
  desc 'download', 'Download data from Jira'
  def download
    load_config options[:config]
    Exporter.instance.download(name_filter: options[:name] || '*')
  end

  option :config
  option :name
  desc 'go', 'Same as running download, followed by export'
  def go
    load_config options[:config]
    Exporter.instance.download(name_filter: options[:name] || '*')

    load_config options[:config]
    Exporter.instance.export(name_filter: options[:name] || '*')
  end

  option :config
  desc 'info', 'Dump information about one issue'
  def info key
    load_config options[:config]
    Exporter.instance.info(key, name_filter: options[:name] || '*')
  end

  no_commands do
    def load_config config_file, file_system: FileSystem.new
      config_file = './config.rb' if config_file.nil?

      if File.exist? config_file
        # The fact that File.exist can see the file does not mean that require will be
        # able to load it. Convert this to an absolute pathname now for require.
        config_file = File.absolute_path(config_file).to_s
      else
        file_system.error "Cannot find configuration file #{config_file.inspect}"
        exit 1
      end

      require_rel 'jirametrics'
      load config_file
    end
  end
end
