# frozen_string_literal: true

require 'cgi'
require 'json'

class Downloader
  attr_accessor :metadata # Used only for testing

  # For testing only
  attr_reader :start_date_in_query

  def initialize download_config:, json_file_loader: JsonFileLoader.new
    @metadata = {}
    @download_config = download_config
    @target_path = @download_config.project_config.target_path
    @json_file_loader = json_file_loader
  end

  def run
    load_jira_config(@download_config.project_config.jira_config)
    load_metadata

    if @metadata['no-download']
      puts "Skipping download of #{@download_config.project_config.file_prefix}. Found no-download in meta file"
      return
    end

    remove_old_files
    download_issues
    download_statuses
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

    escaped_jql = CGI.escape make_jql
    max_results = 100
    start_at = 0
    total = 1
    while start_at < total
      command = make_curl_command url: "#{@jira_url}/rest/api/2/search" \
        "?jql=#{escaped_jql}&maxResults=#{max_results}&startAt=#{start_at}&expand=changelog"

      json = JSON.parse call_command(command)
      exit_if_call_failed json

      json['issues'].each do |issue_json|
        write_json(issue_json, "#{path}#{issue_json['key']}.json")
      end

      total = json['total'].to_i
      max_results = json['maxResults']

      message = " Downloaded #{start_at + 1}-#{[start_at + max_results, total].min} of #{total} issues to #{path} "
      puts ('=' * message.length), message, ('=' * message.length)

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
    command = make_curl_command url: "\"#{@jira_url}/rest/api/2/status\""
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

      if json['type'] == 'scrum'
        download_sprints board_id
      end
    end
  end

  def download_sprints board_id
    file_prefix = @download_config.project_config.file_prefix

    max_results = 100
    start_at = 0
    total = 1
    while start_at < total
      command = make_curl_command url: "#{@jira_url}/rest/agile/1.0/board/#{board_id}/sprint?" \
        "maxResults=#{max_results}&startAt=#{start_at}"

      json = JSON.parse call_command(command)
      exit_if_call_failed json

      write_json json, "#{@target_path}#{file_prefix}_board_#{board_id}_sprints_#{start_at}.json"

      total = json['total'].to_i
      max_results = json['maxResults']
      start_at += json['values'].size
    end
  end

  def write_json json, filename
    file_path = File.dirname(filename)
    FileUtils.mkdir_p file_path unless File.exist?(file_path)

    File.open(filename, 'w') do |file|
      file.write(JSON.pretty_generate(json))
    end
  end

  def metadata_pathname
    "#{@target_path}#{@download_config.project_config.file_prefix}_meta.json"
  end

  def load_metadata
    # If we've never done a download before then this file won't be there. That's ok.
    return unless File.exist? metadata_pathname

    hash = JSON.parse(File.read metadata_pathname)

    # If there's no version identifier then this is the old format of metadata. Throw it away and start fresh.
    if hash['version']
      hash.each do |key, value|
        value = Date.parse(value) if value =~ /^\d{4}-\d{2}-\d{2}$/
        @metadata[key] = value
      end
    end

    # Even if this is the old format, we want to obey this one tag
    @metadata['no-download'] = hash['no-download'] if hash['no-download']
  end

  def save_metadata
    raise "We didn't run any queries. Why are we saving metadata again?" unless @start_date_in_query

    @metadata['version'] = 1
    @metadata['earliest_date_start'] = @download_date_range.begin if @metadata['earliest_date_start'].nil?

    @metadata['date_start_from_last_query'] = @start_date_in_query

    @metadata['date_start'] = @download_date_range.begin
    @metadata['date_end'] = @download_date_range.end

    write_json @metadata, metadata_pathname
  end

  def remove_old_files
    file_prefix = @download_config.project_config.file_prefix
    Dir.foreach @target_path do |file|
      next unless file =~ /^#{file_prefix}_\d+\.json$/

      File.unlink "#{@target_path}#{file}"
    end
  end

  def make_jql today: Date.today
    # If JQL was specified then use exactly that without modification
    return @download_config.jql if @download_config.jql

    full_download = metadata['date_end'].nil?

    segments = []
    segments << "project=#{@download_config.project_key.inspect}" unless @download_config.project_key.nil?
    segments << "filter=#{@download_config.filter_name.inspect}" unless @download_config.filter_name.nil?

    raise 'At least one of project_key, filter_name or jql must be specified' if segments.empty?

    where_snippets = []
    where_snippets << '(status changed AND resolved = null)' if full_download
    where_snippets << '(Sprint is not EMPTY)'

    unless @download_config.rolling_date_count.nil?
      @download_date_range = (today.to_date - @download_config.rolling_date_count)..today.to_date

      # For an incremental download, we want to query from the end of the previous one, not from the
      # beginning of the full range.
      @start_date_in_query = metadata['date_end'] || @download_date_range.begin

      start_date_text = @start_date_in_query.strftime '%Y-%m-%d'
      end_date_text = today.strftime '%Y-%m-%d'
      where_snippets << %((status changed DURING ("#{start_date_text} 00:00","#{end_date_text} 23:59")))
    end

    segments << "(#{where_snippets.join(' OR ')})"

    segments.join ' AND '
  end
end
