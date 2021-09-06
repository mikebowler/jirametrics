class Issue
	attr_reader :changes

	def initialize raw_data
		@raw = raw_data
		@changes = []
		@raw['changelog']['histories'].each do |history|
			created = history['created']
			history['items'].each do |item|
				@changes << ChangeItem.new(raw: item, time: created)
			end
		end

		# Initial creation isn't considered a change so Jira doesn't create an entry for that
		@changes << createFakeChangeForCreation

		@changes.reverse!
	end

	def key = @raw['key']
	def type = @raw['fields']['issuetype']['name']
	def summary = @raw['fields']['summary']

	def createFakeChangeForCreation
		created_time = @raw['fields']['created']
		first_status = '--CREATED--'
		unless @changes.empty?
			first_status = @changes[-1].raw['fromString']
		end
		ChangeItem.new time: created_time, field: 'status', value: first_status
	end

	def first_time_in_status *status_names
		@changes.find { |change| change.field == 'status' && status_names.include?(change.value) }&.time
	end

	def first_time_not_in_status *status_names
		@changes.find { |change| change.field == 'status' && status_names.include?(change.value) == false }&.time
	end

	# first_time_for_any_status_change
	# first_time_in_status(...)
	# first_time_not_in_status(...)
	# last_time_in_status(...)
	# last_time_not_in_status(...)
	# first_time_in_status_category(...)
	# last_time_in_status_category(...)
	# first_time_on_board (looking at the board config)


end
