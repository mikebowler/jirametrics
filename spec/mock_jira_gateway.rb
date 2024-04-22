# frozen_string_literal: true

require 'cgi'
require 'json'
require 'English'

class MockJiraGateway < JiraGateway  
  def initialize file_system:
    super file_system: file_system
    @data = {}
  end

  def call_command url
    response = @data[url]
    raise "404 for #{url.inspect}" if response.nil?
    response
  end

  def when url:, response:
    puts "when url: #{url} response: #{response}"
    @data[url] = response
  end
end
