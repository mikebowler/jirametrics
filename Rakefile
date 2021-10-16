# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'require_all'

task default: %i[download extract]

task :initialize_config do
  require_all 'lib'
  require './config'
end

task download: %i[initialize_config] do
  Downloader.new.run
end

task extract: [:initialize_config] do
  Config.instances.each { |config| config.run }
end

task export: [:initialize_config] do
  Exporter.instance.export
end

RSpec::Core::RakeTask.new(:spec)

task test: [:spec]
