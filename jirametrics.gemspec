# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = 'jirametrics'
  spec.version     = '1.0.0'
  spec.summary     = 'Extract Jira metrics'
  spec.description = 'Extract Jira metrics'
  spec.authors     = ['Mike Bowler']
  spec.email       = 'mbowler@gargoylesoftware.com'
  spec.files       = Dir['lib/**/*.rb'] + Dir['bin/*']
  spec.homepage    = 'https://rubygems.org/gems/jirametrics'
  spec.license     = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.0.0'
  spec.add_runtime_dependency 'random-word' #, '~> 1.1', '>= 1.1.4'
  # spec.add_runtime_dependency 'require_all'
spec.add_dependency "require_all" #, "~> 3.2"
  spec.bindir = 'bin'
  spec.executables << 'jirametrics'
end
