# frozen_string_literal: true

require 'cgi'
require 'json'

class Downloader
  def initialize download_config:, json_file_loader: JsonFileLoader.new
    @download_config = download_config
    @target_path = @download_config.project_config.target_path
    @json_file_loader = json_file_loader
  end

  def run
    load_jira_config(@download_config.project_config.jira_config)

    remove_old_files
    download_issues
    download_statuses unless @download_config.project_key.nil?
    download_board_configuration unless @download_config.board_ids.empty?
    save_metadata
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
    command = 'curl'
    command += " --cookie #{@cookies.inspect}" unless @cookies.empty?
    command += " --user #{@jira_email}:#{@jira_api_token}" if @jira_email
    command += ' --request GET'
    command += ' --header "Accept: application/json"'
    command += " --url \"#{url}\""
    command
  end

  def download_issues
    path = "#{@target_path}#{@download_config.project_config.file_prefix}_issues/"
    puts "Creating path #{path}"
    Dir.mkdir(path) unless Dir.exist?(path)

    jql = CGI.escape @download_config.jql
    max_results = 100
    start_at = 0
    total = 1
    while start_at < total
      command = make_curl_command url: "#{@jira_url}/rest/api/2/search" \
        "?jql=#{jql}&maxResults=#{max_results}&startAt=#{start_at}&expand=changelog"

      json = JSON.parse call_command(command)
      exit_if_call_failed json

      json['issues'].each do |issue_json|
        write_json(issue_json, "#{path}#{issue_json['key']}.json")
      end

      # write_json json, "#{@target_path}#{@download_config.project_config.file_prefix}_#{start_at}.json"
      total = json['total'].to_i
      max_results = json['maxResults']
      start_at += json['issues'].size
    end
  end

  def exit_if_call_failed json
    # Sometimes Jira returns the singular form of errorMessage and sometimes the plural. Consistency FTW.
    return unless json['errorMessages'] || json['errorMessage']

    puts JSON.pretty_generate(json)
    exit 1
  end

  def download_statuses
    command = make_curl_command url: "\"#{@jira_url}/rest/api/2/project/#{@download_config.project_key}/statuses\""
    json = JSON.parse call_command(command)

    write_json json, "#{@target_path}#{@download_config.project_config.file_prefix}_statuses.json"
  end

  def download_board_configuration
    @download_config.board_ids.each do |board_id|
      command = make_curl_command url: "#{@jira_url}/rest/agile/1.0/board/#{board_id}/configuration"
      json = JSON.parse call_command(command)
      exit_if_call_failed json

      file_prefix = @download_config.project_config.file_prefix
      write_json json, "#{@target_path}#{file_prefix}_board_#{board_id}_configuration.json"
    end
  end

  def write_json json, filename
    file_path = File.dirname(filename)
    FileUtils.mkdir_p file_path unless File.exist?(file_path)

    File.open(filename, 'w') do |file|
      file.write(JSON.pretty_generate(json))
    end
  end

  def save_metadata
    date_range = @download_config.date_range
    json = {
      'time_start' => date_range.begin.to_datetime,
      'time_end' => end_of_day(date_range.end.to_datetime)
    }

    file_prefix = @download_config.project_config.file_prefix
    write_json json, "#{@target_path}#{file_prefix}_meta.json"
  end

  def end_of_day date
    DateTime.new date.year, date.month, date.day, 23, 59, 59
  end

  def remove_old_files
    file_prefix = @download_config.project_config.file_prefix
    Dir.foreach @target_path do |file|
      next unless file =~ /^#{file_prefix}_\d+\.json$/

      File.unlink "#{@target_path}#{file}"
    end
  end
end
