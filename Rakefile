# frozen_string_literal: true

require 'rspec/core/rake_task'

task default: [:spec]
task test: [:spec] # Aliasing because it's easier than teaching my fingers to not type 'test'

task :initialize_config do # rubocop:disable Rake/Desc
  # Force lib onto the load path to match how it would run when packaged as a gem
  $LOAD_PATH.unshift './lib'

  require 'jirametrics'
  puts "Deprecated: This project is now packaged as the ruby gem 'jirametrics' and should be " \
    'called through that. See https://github.com/mikebowler/jirametrics/wiki'
end

desc 'Download data from Jira'
task download: %i[initialize_config] do
  JiraMetrics.start ['download']
end

desc 'Generate the reports'
task export: [:initialize_config] do
  JiraMetrics.start ['export']
end

desc 'Same as calling download and then export'
task go: [:initialize_config, :download, :export]

RSpec::Core::RakeTask.new(:spec)
