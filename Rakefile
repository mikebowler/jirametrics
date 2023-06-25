# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'require_all'

task default: %i[download export]

task :initialize_config do
  config_file = './config.rb'
  if ENV['config_file']
    config_file = ENV['config_file']
    if File.exist? config_file
      puts "Using config file #{config_file}"
    else
      puts "Cannot find config file #{config_file}"
    end
  end
  puts "config=#{config_file}"
  require_all 'lib'
  require config_file
  exit 1
end

task download: %i[initialize_config] do
  Exporter.instance.download
end

task export: [:initialize_config] do
  Exporter.instance.export
end

RSpec::Core::RakeTask.new(:spec)

task test: [:spec]
