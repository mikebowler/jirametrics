# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'jirametrics'
  s.version     = '1.0.0'
  s.summary     = 'Extract Jira metrics'
  s.description = 'Extract Jira metrics'
  s.authors     = ['Mike Bowler']
  s.email       = 'mbowler@gargoylesoftware.com'
  s.files       = Dir['lib/**/*.rb'] + Dir['bin/*']
  s.homepage    = 'https://rubygems.org/gems/jirametrics'
  s.license     = 'Apache-2.0'
  s.required_ruby_version = '>= 3.0.0'
  spec.add_runtime_dependency 'example', '~> 1.1', '>= 1.1.4'
  spec.bindir = 'bin'
  spec.executables << 'jirametrics'
end
