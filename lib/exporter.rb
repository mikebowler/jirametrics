# frozen_string_literal: true

class Exporter
  # attr_accessor :target_path, :jira_config

  def self.configure &block
    exporter = Exporter.new
    exporter.instance_eval(&block)
    @@instance = exporter
  end

  def self.instance = @@instance

  def initialize
    @projects = []
    # @target_path = 'target/'
  end

  def export
    @projects.each do |project|
      project.run
    end
  end

  def project &block
    raise 'target_path was never set!' if @target_path.nil?
    @projects << ConfigProject.new(exporter: self, target_path: @target_path, block: block)
  end

  def xproject *args; end

  def target_path *arg
    @target_path = arg[0] unless arg.empty?
    @target_path
  end

  def jira_config *arg
    @jira_config = arg[0] unless arg.empty?
    @jira_config
  end
end
