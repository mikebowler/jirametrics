class Issue
    attr_reader :changes

    def initialize raw_data
        @raw = raw_data
        @changes = []

        if @raw['changelog'].nil?
            raise "No changelog found in issue #{@raw['key']}. This is likely because when we pulled the data" \
            " from Jira, we didn't specifiy expand=changelog. Without that changelog, nothing else is going to" \
            " work so stopping now."
        end 
            
        @raw['changelog']['histories'].each do |history|
            created = history['created']
            history['items'].each do |item|
                @changes << ChangeItem.new(raw: item, time: created)
            end
        end

        # It might appear that Jira already returns these in order but we've found different
        # versions of Server/Cloud return the changelog in different orders so we sort them.
        sort_changes!

        # Initial creation isn't considered a change so Jira doesn't create an entry for that
        @changes.insert 0, createFakeChangeForCreation(@changes)

    end

    def sort_changes!
        @changes.sort! do |a,b| 
            # It's common that a resolved will happen at the same time as a status change. 
            # Put them in a defined order so tests can be deterministic.
            compare = a.time <=> b.time
            compare = 1 if compare == 0 && a.resolution?
            compare
        end
    end

    def key = @raw['key']
    def type = @raw['fields']['issuetype']['name']
    def summary = @raw['fields']['summary']

    def createFakeChangeForCreation existing_changes
        created_time = @raw['fields']['created']
        first_status = existing_changes.find {|change| change.status?}&.old_value || '--CREATED--'
        ChangeItem.new time: created_time, field: 'status', value: first_status
    end

    def first_time_in_status *status_names
        @changes.find { |change| change.status? && status_names.include?(change.value) }&.time
    end

    def first_time_not_in_status *status_names
        @changes.find { |change| change.status? && status_names.include?(change.value) == false }&.time
    end

    def still_in
        time = nil
        @changes.each do |change|
            next unless change.status?
            current_status_matched = yield change

            if current_status_matched && time.nil?
                time = change.time
            elsif !current_status_matched && time
                time = nil
            end
        end
        time
    end
    private :still_in

    # If it ever entered one of these statuses and it's still there then what was the last time it entered
    def still_in_status *status_names
        still_in do |change|
            status_names.include?(change.value)
        end
    end

    # If it ever entered one of these categories and it's still there then what was the last time it entered
    def still_in_status_category config, *category_names
        still_in do |change|
            # puts key
            category = config.category_for type: type, status: change.value
            category_names.include? category
        end
    end

    def first_status_change_after_created
        @changes[1..].find { |change| change.status? }&.time
    end

    def first_time_in_status_category config, *category_names
        @changes.each do | change |
            next unless change.status?
            category = config.category_for type: type, status: change.value
            # category = config.status_category_mappings[self.type][change.value]
            return change.time if category_names.include? category
        end
        nil
    end

    # last_time_not_in_status(...)
    # first_time_in_status_category(...)
    # last_time_in_status_category(...)
    # first_time_on_board (looking at the board config)


end
