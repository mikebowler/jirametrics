# frozen_string_literal: true

require 'cgi'
require 'json'
require 'English'

class MockJiraGateway < JiraGateway  
  def initialize file_system:
    super file_system: file_system
  end

  def call_command
  end

end
