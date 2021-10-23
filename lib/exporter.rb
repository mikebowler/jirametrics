# frozen_string_literal: true

class Exporter
  attr_reader :project_configs

  def self.configure &block
    exporter = Exporter.new
    exporter.instance_eval(&block)
    @@instance = exporter
  end

  def self.instance = @@instance

  def initialize
    @project_configs = []
    # @target_path = 'target/'
  end

  def export
    @project_configs.each do |project|
      project.evaluate_next_level
      project.run
    end
  end

  def download
    @project_configs.each do |project|
      project.evaluate_next_level
      project.download_config.run
      Downloader.new(download_config: project.download_config).run
    end
  end

  def project &block
    raise 'target_path was never set!' if @target_path.nil?
    raise 'jira_config not set' if @jira_config.nil?

    @project_configs << ProjectConfig.new(
      exporter: self, target_path: @target_path, jira_config: @jira_config, block: block
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
    @jira_config = JsonFileLoader.new.load(filename) unless filename.nil?
    @jira_config
  end
end
