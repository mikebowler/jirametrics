# frozen_string_literal: true

require 'fileutils'

class Exporter
  attr_reader :project_configs
  attr_accessor :file_system

  def self.configure &block
    logfile_name = 'jirametrics.log'
    logfile = File.open logfile_name, 'w'
    file_system = FileSystem.new
    file_system.logfile = logfile
    file_system.logfile_name = logfile_name

    exporter = Exporter.new file_system: file_system

    exporter.instance_eval(&block)
    @@instance = exporter
  end

  def self.instance = @@instance

  def initialize file_system: FileSystem.new
    @project_configs = []
    @target_path = '.'
    @holiday_dates = []
    @downloading = false
    @file_system = file_system

    timezone_offset '+00:00'
  end

  def export name_filter:
    each_project_config(name_filter: name_filter) do |project|
      project.evaluate_next_level
      project.run
    end
  end

  def download name_filter:
    @downloading = true
    each_project_config(name_filter: name_filter) do |project|
      project.evaluate_next_level
      next if project.aggregated_project?

      unless project.download_config
        raise "Project #{project.name.inspect} is missing a download section in the config. " \
          'That is required in order to download'
      end

      project.download_config.run
      downloader = Downloader.create(
        download_config: project.download_config,
        file_system: file_system,
        jira_gateway: JiraGateway.new(file_system: file_system)
      )
      downloader.run
    end
    puts "Full output from downloader in #{file_system.logfile_name}"
  end

  def info keys, name_filter:
    selected = []
    each_project_config(name_filter: name_filter) do |project|
      project.evaluate_next_level

      project.run load_only: true
      project.issues.each do |issue|
        selected << [project, issue] if keys.include? issue.key
      end
    rescue => e # rubocop:disable Style/RescueStandardError
      # This happens when we're attempting to load an aggregated project because it hasn't been
      # properly initialized. Since we don't care about aggregated projects, we just ignore it.
      raise unless e.message.start_with? 'This is an aggregated project and issues should have been included'
    end

    if selected.empty?
      file_system.log "No issues found to match #{keys.collect(&:inspect).join(', ')}"
    else
      selected.each do |project, issue|
        file_system.log "\nProject #{project.name}", also_write_to_stderr: true
        file_system.log issue.dump, also_write_to_stderr: true
      end
    end
  end

  def each_project_config name_filter:
    @project_configs.each do |project|
      yield project if project.name.nil? || File.fnmatch(name_filter, project.name)
    end
  end

  def downloading?
    @downloading
  end

  def project name: nil, &block
    raise 'jira_config not set' if @jira_config.nil?

    @project_configs << ProjectConfig.new(
      exporter: self, target_path: @target_path, jira_config: @jira_config, block: block, name: name
    )
  end

  def xproject *args; end

  def target_path path = nil
    unless path.nil?
      @target_path = path
      @target_path += File::SEPARATOR unless @target_path.end_with? File::SEPARATOR
      FileUtils.mkdir_p @target_path
    end
    @target_path
  end

  def jira_config filename = nil
    if filename
      @jira_config = file_system.load_json(filename, fail_on_error: false)
      raise "Unable to load Jira configuration file and cannot continue: #{filename.inspect}" if @jira_config.nil?

      @jira_config['url'] = $1 if @jira_config['url'] =~ /^(.+)\/+$/
    end
    @jira_config
  end

  def timezone_offset offset = nil
    @timezone_offset = offset unless offset.nil?
    @timezone_offset
  end

  def holiday_dates *args
    unless args.empty?
      dates = []
      args.each do |arg|
        if arg =~ /^(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})$/
          Date.parse($1).upto(Date.parse($2)).each { |date| dates << date }
        else
          dates << Date.parse(arg)
        end
      end
      @holiday_dates = dates
    end
    @holiday_dates
  end
end
