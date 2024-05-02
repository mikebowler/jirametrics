# frozen_string_literal: true

require 'cgi'
require 'json'
require 'English'

class MockJiraGateway < JiraGateway
  def initialize file_system:
    super(file_system: file_system)
    @data = {}
  end

  def call_url relative_url:
    response = @data[relative_url]
    raise "404 for #{relative_url.inspect}" if response.nil?

    response
  end

  def call_command url
    call_url relative_url: url
  end

  def when url:, response:
    @data[url] = response
  end
end
