# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'require_all'

task default: %i[download extract]

task :initialize_config do
  require_all 'lib'
  require './config'
end

task download: %i[initialize_config] do
  Exporter.instance.download
end

task export: [:initialize_config] do
  Exporter.instance.export
end

RSpec::Core::RakeTask.new(:spec)

task test: [:spec]
