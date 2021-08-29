require 'cgi'
require 'json'

class Downloader
	OUTPUT_PATH = 'target/'

	def initialize
		config = JSON.parse File.read('jira_config.json')
		@jira_url = config['url']
		@jira_email = config['email']
		@jira_api_token = config['api_token']
	end

	def download_issues output_file_prefix
		jql = CGI.escape 'project=SP'
		max_results = 100
		start_at = 0
		total = 1
        while start_at < total
            command = <<-COMMAND
            	curl --request GET \
            	--url "#{ @jira_url }/rest/api/2/search?jql=#{ jql }&maxResults=#{max_results}&startAt=#{start_at}&expand=changelog" \
                --user #{ @jira_email }:#{ @jira_api_token } \
                --header "Accept: application/json"
            COMMAND
            puts "About to call curl"
            puts command
            json = JSON.parse `#{command}`
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

    def download_columns output_file_prefix, board_id
		command = <<-COMMAND
			curl --request GET \
            --url #{@jira_url}/rest/agile/1.0/board/#{board_id}/configuration \
            --user #{@jira_email}:#{@jira_api_token} \
            --header Accept: application/json
         COMMAND

        json = JSON.parse `#{command}`
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

downloader = Downloader.new
downloader.download_columns 'foo', 1
downloader.download_issues 'foo'

