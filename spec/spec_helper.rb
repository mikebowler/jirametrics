# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  SimpleCov.add_filter do |src_file|
    File.basename(src_file.filename) == 'config.rb'
  end
end

require 'require_all'
require_all 'lib'

def make_test_filename basename
  "spec/tmp/#{basename}"
end

def load_issue key
  Issue.new(raw: JSON.parse(File.read("spec/testdata/#{key}.json")))
end

def defaultCycletimeConfig
  block = lambda do |_|
    start_at created
    stop_at last_resolution
  end
  CycleTimeConfig.new parent_config: nil, label: nil, block: block
end