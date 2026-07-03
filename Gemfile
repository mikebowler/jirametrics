# frozen_string_literal: true

source 'https://rubygems.org'

# ruby '>= 3.0.0'

gem 'csv' # No longer core in ruby 3.4
gem 'json-schema' # Required directly by lib/jirametrics/mcp_server.rb (was only pulled in transitively by old mcp)
gem 'mcp'
gem 'rake'
gem 'random-word'
gem 'require_all'
gem 'rspec'
gem 'rubocop', require: false
gem 'rubocop-performance', require: false
gem 'rubocop-rake', require: false
gem 'rubocop-rspec', require: false
gem 'simplecov'
gem 'thor'

# Mutation testing is only run on MRI. Keeping it off JRuby avoids mutant's
# irb -> rdoc -> rbs chain, whose native extension can't build on JRuby.
platforms :ruby do
  gem 'mutant-rspec', require: false
end
