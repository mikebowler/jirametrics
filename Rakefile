require 'rspec/core/rake_task'
require 'require_all'
require_all 'lib'
require './config'
require './downloader'

task :default => [:download, :extract]

task :download do
	Downloader.new 
end

task :extract do
	Config.instances.each { |config| config.run }
end

RSpec::Core::RakeTask.new(:spec)
