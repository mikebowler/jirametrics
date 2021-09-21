require 'cgi'
require 'json'

class Downloader
    OUTPUT_PATH = 'target/'

    def initialize
        load_jira_config
        Config.instances.each do |config|
            download_issues config
            download_statuses(config) unless config.project_key.nil?
        end
    end

    def load_jira_config
        jira_config = JSON.parse File.read('jira_config.json')
        @jira_url = jira_config['url']
        @jira_email = jira_config['email']
        @jira_api_token = jira_config['api_token']
        @cookies = jira_config['cookies'].collect { |key, value| "#{key}=#{value}" }.join(';')
    end

    def call_command command
        puts '----', command.gsub(/\s+/, ' '), ''
        `#{command}`
    end
    def download_issues config
        output_file_prefix = config.file_prefix
        jql = CGI.escape config.jql
        max_results = 100
        start_at = 0
        total = 1
        # --user #{ @jira_email }:#{ @jira_api_token } \
        while start_at < total
            command = "curl"
            command += " --cookie #{@cookies.inspect} " if @cookies
            command += " --user #{ @jira_email }:#{ @jira_api_token }" if @jira_email
            command += ' --request GET'
            command += " --url \"#{ @jira_url }/rest/api/2/search"
            command += "?jql=#{ jql }&maxResults=#{max_results}&startAt=#{start_at}&expand=changelog\"" \

            json = JSON.parse call_command(command)
            if json['errorMessages']
                puts JSON.pretty_generate(json)
                exit 1
            end
            output_file = "#{OUTPUT_PATH}#{output_file_prefix}_#{start_at}.json"
            File.open(output_file, 'w') do |file|
                file.write(JSON.pretty_generate(json))
            end
            total = json['total'].to_i
            max_results = json['maxResults']
            start_at += json['issues'].size
        end
        # self.create_meta_json(output_file_prefix, meta_data)
    end

    def download_statuses config
        command = "curl"
        command += " --cookie #{@cookies.inspect} " if @cookies
        command += " --user #{ @jira_email }:#{ @jira_api_token }" if @jira_email
        command += ' --request GET'
        command += " --url \"#{ @jira_url }/rest/api/2/project/#{ config.project_key }/statuses\""

        json = JSON.parse call_command(command)

        output_file = "#{OUTPUT_PATH}#{config.file_prefix}_statuses.json"
        File.open(output_file, 'w') do |file|
            file.write(JSON.pretty_generate(json))
        end
    end

    def download_columns output_file_prefix, board_id
        command = <<-COMMAND
            curl --request GET \
            --url #{@jira_url}/rest/agile/1.0/board/#{board_id}/configuration \
            --user #{@jira_email}:#{@jira_api_token} \
            --header "Accept: application/json"
         COMMAND

        json = JSON.parse call_command(command)
        if json['errorMessages']
            puts JSON.pretty_generate(json)
            exit 1
        end

        output_file = "#{OUTPUT_PATH}#{output_file_prefix}_configuration.json"
        File.open(output_file, 'w') do |file|
            file.write(JSON.pretty_generate(json))
        end

        puts command
    end
end

