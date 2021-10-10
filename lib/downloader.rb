# frozen_string_literal: true

require 'cgi'
require 'json'

class Downloader
  OUTPUT_PATH = 'target/'

  def initialize instances = Config.instances, json_file_loader = JsonFileLoader.new
    @config_instances = instances
    @json_file_loader = json_file_loader
  end

  def run
    @config_instances.each do |config|
      load_jira_config( @json_file_loader.load("jira_config_#{config.jira_config}.json") )
      download_issues config
      download_statuses(config) unless config.project_key.nil?
      download_board_configuration(config) unless config.board_id.nil?
    end
  end

  def load_jira_config jira_config
    @jira_url = jira_config['url']
    @jira_email = jira_config['email']
    @jira_api_token = jira_config['api_token']
    @cookies = (jira_config['cookies'] || []).collect { |key, value| "#{key}=#{value}" }.join(';')
  end

  def call_command command
    puts '----', command.gsub(/\s+/, ' '), ''
    `#{command}`
  end

  def make_curl_command url:
    command = "curl"
    command += " --cookie #{@cookies.inspect}" unless @cookies.empty?
    command += " --user #{ @jira_email }:#{ @jira_api_token }" if @jira_email
    command += ' --request GET'
    command += ' --header "Accept: application/json"'
    command += " --url \"#{url}\""
    command
  end

  def download_issues config
    output_file_prefix = config.file_prefix
    jql = CGI.escape config.jql
    max_results = 100
    start_at = 0
    total = 1
    while start_at < total
      command = make_curl_command url: "#{ @jira_url }/rest/api/2/search" \
        "?jql=#{ jql }&maxResults=#{max_results}&startAt=#{start_at}&expand=changelog"

      json = JSON.parse call_command(command)
      exit_if_call_failed json

      write_json json, "#{OUTPUT_PATH}#{output_file_prefix}_#{start_at}.json"
      total = json['total'].to_i
      max_results = json['maxResults']
      start_at += json['issues'].size
    end
    # self.create_meta_json(output_file_prefix, meta_data)
  end

  def exit_if_call_failed json
    # Sometimes Jira returns the singular form of errorMessage and sometimes the plural. Consistency FTW.
    if json['errorMessages'] || json['errorMessage']
      puts JSON.pretty_generate(json)
      exit 1
    end
  end

  def download_statuses config
    command = make_curl_command url: "\"#{ @jira_url }/rest/api/2/project/#{ config.project_key }/statuses\""
    json = JSON.parse call_command(command)

    write_json json, "#{OUTPUT_PATH}#{config.file_prefix}_statuses.json"
  end

  def download_board_configuration config
    command = make_curl_command url: "#{@jira_url}/rest/agile/1.0/board/#{config.board_id}/configuration"
    json = JSON.parse call_command(command)
    exit_if_call_failed json

    write_json json, "#{OUTPUT_PATH}#{config.file_prefix}_board_configuration.json"
  end

  def write_json json, filename
    File.open(filename, 'w') do |file|
      file.write(JSON.pretty_generate(json))
    end
  end
end

