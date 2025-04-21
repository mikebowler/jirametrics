# frozen_string_literal: true

require 'cgi'
require 'json'
require 'English'

class JiraGateway
  attr_accessor :ignore_ssl_errors, :jira_url

  def initialize file_system:
    @file_system = file_system
  end

  def call_url relative_url:
    command = make_curl_command url: "#{@jira_url}#{relative_url}"
    result = call_command command
    begin
      json = JSON.parse(result)
    rescue # rubocop:disable Style/RescueStandardError
      raise "Error when parsing result: #{result.inspect}"
    end

    raise "Download failed with: #{JSON.pretty_generate(json)}" unless json_successful?(json)

    json
  end

  def call_command command
    log_entry = "  #{command.gsub(/\s+/, ' ')}"
    log_entry = log_entry.gsub(@jira_api_token, '[API_TOKEN]') if @jira_api_token
    @file_system.log log_entry

    result = `#{command}`
    @file_system.log result unless $CHILD_STATUS.success?
    return result if $CHILD_STATUS.success?

    @file_system.log "Failed call with exit status #{$CHILD_STATUS.exitstatus}."
    raise "Failed call with exit status #{$CHILD_STATUS.exitstatus}. " \
      "See #{@file_system.logfile_name} for details"
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

  def make_curl_command url:
    command = +''
    command << 'curl'
    command << ' -L' # follow redirects
    command << ' -s' # silent
    command << ' -k' if @ignore_ssl_errors # insecure
    command << " --cookie #{@cookies.inspect}" unless @cookies.empty?
    command << " --user #{@jira_email}:#{@jira_api_token}" if @jira_api_token
    command << " -H \"Authorization: Bearer #{@jira_personal_access_token}\"" if @jira_personal_access_token
    command << ' --request GET'
    command << ' --header "Accept: application/json"'
    command << " --url \"#{url}\""
    command
  end

  def json_successful? json
    return false if json.is_a?(Hash) && (json['error'] || json['errorMessages'] || json['errorMessage'])
    return false if json.is_a?(Array) && json.first == 'errorMessage'

    true
  end
end
