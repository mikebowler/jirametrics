# frozen_string_literal: true

require 'cgi'
require 'json'
require 'English'
require 'open3'

class JiraGateway
  attr_accessor :ignore_ssl_errors
  attr_reader :jira_url, :settings, :file_system

  def initialize file_system:, jira_config:, settings:
    @file_system = file_system
    load_jira_config(jira_config)
    @settings = settings
    @ignore_ssl_errors = settings['ignore_ssl_errors']
  end

  def post_request relative_url:, payload:
    command = make_curl_command url: "#{@jira_url}#{relative_url}", method: 'POST'
    exec_and_parse_response command: command, stdin_data: payload
  end

  def exec_and_parse_response command:, stdin_data:
    log_entry = "  #{command.gsub(/\s+/, ' ')}"
    log_entry = sanitize_message log_entry
    @file_system.log log_entry

    stdout, stderr, status = capture3(command, stdin_data: stdin_data)
    unless status.success?
      @file_system.log "Failed call with exit status #{status.exitstatus}!"
      @file_system.log "Returned (stdout): #{stdout.inspect}"
      @file_system.log "Returned (stderr): #{stderr.inspect}"
      raise "Failed call with exit status #{status.exitstatus}. " \
        "See #{@file_system.logfile_name} for details"
    end

    @file_system.log "Returned (stderr): #{stderr.inspect}" unless stderr == ''
    raise 'no response from curl on stdout' if stdout == ''

    parse_response(command: command, result: stdout)
  end

  def capture3 command, stdin_data:
    # In it's own method so we can mock it out in tests
    Open3.capture3(command, stdin_data: stdin_data)
  end

  def call_url relative_url:
    command = make_curl_command url: "#{@jira_url}#{relative_url}"
    exec_and_parse_response command: command, stdin_data: nil
  end

  def parse_response command:, result:
    begin
      json = JSON.parse(result)
    rescue # rubocop:disable Style/RescueStandardError
      message = "Unable to parse results from #{sanitize_message(command)}"
      @file_system.error message, more: result
      raise message
    end

    raise "Download failed with: #{JSON.pretty_generate(json)}" unless json_successful?(json)

    json
  end

  def sanitize_message message
    token = @jira_api_token || @jira_personal_access_token
    raise 'Neither Jira API Token or personal access token has been set' unless token

    message.gsub(token, '[API_TOKEN]')
  end

  def load_jira_config jira_config
    @jira_url = jira_config['url']
    raise 'Must specify URL in config' if @jira_url.nil?

    @jira_email = jira_config['email']
    @jira_api_token = jira_config['api_token']
    @jira_personal_access_token = jira_config['personal_access_token']

    raise 'When specifying an api-token, you must also specify email' if @jira_api_token && !@jira_email

    if @jira_api_token && @jira_personal_access_token
      raise "You can't specify both an api-token and a personal-access-token. They don't work together."
    end

    @cookies = (jira_config['cookies'] || []).collect { |key, value| "#{key}=#{value}" }.join(';')
  end

  def make_curl_command url:, method: 'GET'
    command = +''
    command << 'curl'
    command << ' -L' # follow redirects
    command << ' -s' # silent
    command << ' -k' if @ignore_ssl_errors # insecure
    command << " --cookie #{@cookies.inspect}" unless @cookies.empty?
    command << " --user #{@jira_email}:#{@jira_api_token}" if @jira_api_token
    command << " -H \"Authorization: Bearer #{@jira_personal_access_token}\"" if @jira_personal_access_token
    command << " --request #{method}"
    if method == 'POST'
      command << ' --data @-'
      command << ' --header "Content-Type: application/json"'
    end
    command << ' --header "Accept: application/json"'
    command << ' --show-error --fail' # Better diagnostics when the server returns an error
    command << " --url \"#{url}\""
    command
  end

  def json_successful? json
    return false if json.is_a?(Hash) && (json['error'] || json['errorMessages'] || json['errorMessage'])
    return false if json.is_a?(Array) && json.first == 'errorMessage'

    true
  end

  def cloud?
    @jira_url.downcase.end_with? '.atlassian.net'
  end
end
