# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = 'jirametrics'
  spec.version     = '1.0.0.pre2'
  spec.summary     = 'Extract Jira metrics'
  spec.description = 'Tool to extract metrics from Jira and export to either a report or to CSV files'
  spec.authors     = ['Mike Bowler']
  spec.email       = 'mbowler@gargoylesoftware.com'
  spec.files       = Dir['lib/**/*.rb'] + Dir['lib/**/*.erb'] + Dir['bin/*']
  spec.homepage    = 'https://rubygems.org/gems/jirametrics'
  spec.license     = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.0.0'
  spec.add_dependency 'random-word', '~> 2.1.1'
  spec.add_dependency 'require_all', '~> 3.0.0'
  spec.add_dependency 'thor', '~> 1.2.2'
  spec.bindir = 'bin'
  spec.executables << 'jirametrics'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.add_development_dependency 'rspec', '~> 3.4'
end
