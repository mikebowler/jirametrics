require 'simplecov'
SimpleCov.start do
	enable_coverage :branch
	add_filter '/spec/'
end

require 'require_all'
require_all 'lib'
