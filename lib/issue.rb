class Issue
    attr_reader :changes

    def initialize raw_data
        @raw = raw_data
        @changes = []
        if @raw['changelog'].nil?
            raise "No changelog found in issue #{@raw['key']}"
        else
            @raw['changelog']['histories'].each do |history|
                created = history['created']
                history['items'].each do |item|
                    @changes << ChangeItem.new(raw: item, time: created)
                end
            end
        end


        # Initial creation isn't considered a change so Jira doesn't create an entry for that
        @changes << createFakeChangeForCreation

        @changes.sort! do |a,b| 
            # It's common that a resolved will happen at the same time as a status change. Put them in a defined order
            compare = a.time <=> b.time
            compare = 1 if compare == 0 && a.resolution?
            compare
        end
    end

    def debug? =  key == 'CCDRAPTORS-4584'

    def key = @raw['key']
    def type = @raw['fields']['issuetype']['name']
    def summary = @raw['fields']['summary']

    def createFakeChangeForCreation
        created_time = @raw['fields']['created']
        first_status = '--CREATED--'
        unless @changes.empty?
            first_status = @changes[-1].raw['fromString'] || first_status
        end
        ChangeItem.new time: created_time, field: 'status', value: first_status
    end

    def first_time_in_status *status_names
        @changes.find { |change| change.status? && status_names.include?(change.value) }&.time
    end

    def first_time_not_in_status *status_names
        @changes.find { |change| change.status? && status_names.include?(change.value) == false }&.time
    end

    def last_time_in_status *status_names
        @changes.reverse.find { |change| change.status? && status_names.include?(change.value) }&.time
    end

    def first_time_for_any_status_change
        @changes[1..].find { |change| change.status? }&.time
    end

    def first_time_in_status_category config, *category_names
        @changes.each do | change |
            next unless change.status?
            category = config.status_category_mappings[self.type][change.value]
            return change.time if category_names.include? category
        end
        nil
    end

    # last_time_not_in_status(...)
    # first_time_in_status_category(...)
    # last_time_in_status_category(...)
    # first_time_on_board (looking at the board config)


end
