# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = 'jirametrics'
  spec.version     = '2.4'
  spec.summary     = 'Extract Jira metrics'
  spec.description = 'Tool to extract metrics from Jira and export to either a report or to CSV files'
  spec.authors     = ['Mike Bowler']
  spec.email       = 'mbowler@gargoylesoftware.com'
  spec.files       = Dir['lib/**/*.{rb,json,css,erb}'] + Dir['bin/*']
  spec.homepage    = 'https://github.com/mikebowler/jirametrics'
  spec.license     = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.0.0'
  spec.add_dependency 'random-word', '~> 2.1.1'
  spec.add_dependency 'require_all', '~> 3.0.0'
  spec.add_dependency 'thor', '~> 1.2.2'
  spec.bindir = 'bin'
  spec.executables << 'jirametrics'
  spec.metadata = {
    'rubygems_mfa_required' => 'true',
    'bug_tracker_uri'       => 'https://github.com/mikebowler/jirametrics/issues',
    'changelog_uri'         => 'https://github.com/mikebowler/jirametrics/wiki/Changes',
    'documentation_uri'     => 'https://github.com/mikebowler/jirametrics/wiki'
  }
end
