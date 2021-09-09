require 'simplecov'
SimpleCov.start do
	enable_coverage :branch
	add_filter '/spec/'
	add_filter 'config.rb'
end

require 'require_all'
require_all 'lib'
