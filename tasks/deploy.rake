# frozen_string_literal: true

require_relative 'gem_deployer'

desc 'Build the gem and install it locally'
task :install do
  GemDeployer.new.build_and_install
end

desc 'Deploy a stable release to RubyGems and GitHub'
task :release do
  GemDeployer.new.run
end

desc 'Deploy a pre-release to RubyGems'
task :prerelease do
  GemDeployer.new.run_prerelease
end
