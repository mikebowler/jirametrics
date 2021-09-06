require 'require_all'
require_all 'lib'

class Config < ConfigBase
	export prefix: 'foo', project: 'SP' do
		issues.each do |issue|
			# Remove specific changes that we want to ignore
		end

		columns write_headers: true do
			date 'Start', first_time_not_in_status('Backlog')
		    date 'Done', last_time_in_status('Done')
		    string 'Type', type
		    string 'Key', key
		    string 'Summary', summary
		end
	end
end

