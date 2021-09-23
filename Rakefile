require 'rspec/core/rake_task'
require 'require_all'

task :default => [:download, :extract]

task :initialize_config do 
	require_all 'lib'
	require './config'
end

task :download => [:initialize_config] do
	Downloader.new 
end

task :extract => [:initialize_config] do
	Config.instances.each { |config| config.run }
end

RSpec::Core::RakeTask.new(:spec)

task :test => [:spec]