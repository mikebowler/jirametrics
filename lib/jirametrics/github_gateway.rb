# frozen_string_literal: true

require 'cgi'
require 'json'
require 'English'
require 'open3'

class GitHubGateway
  attr_reader :owner, :repo, :file_system

  def initialize file_system:, owner:, repo:, token:
    @file_system = file_system
    @owner = owner
    @repo = repo
    @token = token

    raise 'Must specify owner' if @owner.nil? || @owner.empty?
    raise 'Must specify repo' if @repo.nil? || @repo.empty?
    raise 'Must specify token' if @token.nil? || @token.empty?
  end

  def api_url
    "https://api.github.com/repos/#{@owner}/#{@repo}/commits"
  end

  def get_commits page: 1, per_page: 100
    url = "#{api_url}?page=#{page}&per_page=#{per_page}"
    command = make_curl_command(url: url)
    exec_and_parse_response(command: command, stdin_data: nil)
  end

  def get_all_commits
    all_commits = []
    page = 1
    per_page = 100

    loop do
      url = "#{api_url}?page=#{page}&per_page=#{per_page}"
      command = make_curl_command(url: url)
      log_entry = "  #{command.gsub(/\s+/, ' ')}"
      log_entry = sanitize_message log_entry
      @file_system.log log_entry

      stdout, stderr, status = capture3(command, stdin_data: nil)

      unless status.success?
        @file_system.log "Failed call with exit status #{status.exitstatus}!"
        @file_system.log "Returned (stdout): #{stdout.inspect}"
        @file_system.log "Returned (stderr): #{stderr.inspect}"
        raise "Failed call with exit status #{status.exitstatus}. " \
          "See #{@file_system.logfile_name} for details"
      end

      @file_system.log "Returned (stderr): #{stderr.inspect}" unless stderr == ''
      raise 'no response from curl on stdout' if stdout == ''

      headers, body = parse_headers_and_body(stdout)
      commits = parse_response(command: command, result: body)

      all_commits.concat(commits)

      # Check if there's a next page
      link_header = headers['link'] || headers['Link']
      next_page_url = extract_next_page_url(link_header)

      break unless next_page_url

      page += 1
    end

    all_commits
  end

  def make_curl_command url:
    command = +''
    command << 'curl'
    command << ' -L' # follow redirects
    command << ' -s' # silent
    command << ' -i' # include headers
    command << " -H \"Authorization: token #{@token}\""
    command << ' --request GET'
    command << ' --header "Accept: application/json"'
    command << ' --show-error --fail' # Better diagnostics when the server returns an error
    command << " --url \"#{url}\""
    command
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

    headers, body = parse_headers_and_body(stdout)
    parse_response(command: command, result: body)
  end

  def capture3 command, stdin_data:
    # In it's own method so we can mock it out in tests
    Open3.capture3(command, stdin_data: stdin_data)
  end

  def parse_headers_and_body output
    # Split on first blank line (which separates headers from body)
    parts = output.split(/\r?\n\r?\n/, 2)
    return [{}, output] if parts.length < 2

    headers_text = parts[0]
    body = parts[1]

    headers = {}
    headers_text.split(/\r?\n/).each do |line|
      next if line.match?(/^HTTP\/\d\.\d/) # Skip status line

      if line.include?(':')
        key, value = line.split(':', 2)
        headers[key.strip.downcase] = value.strip
      end
    end

    [headers, body]
  end

  def extract_next_page_url link_header
    return nil unless link_header

    # Parse Link header: <url1>; rel="next", <url2>; rel="prev"
    matches = link_header.scan(/<([^>]+)>;\s*rel="next"/i)
    return matches.first[0] if matches.any? && matches.first

    nil
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
    return message unless @token

    message.gsub(@token, '[API_TOKEN]')
  end

  def json_successful? json
    return false if json.is_a?(Hash) && json['message'] && json['documentation_url']
    return true if json.is_a?(Array)

    true
  end
end

