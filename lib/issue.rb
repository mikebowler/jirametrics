# frozen_string_literal: true

class Issue
  attr_reader :changes, :raw

  def initialize raw_data
    @raw = raw_data
    @changes = []

    if @raw['changelog'].nil?
      raise "No changelog found in issue #{@raw['key']}. This is likely because when we pulled the data" \
      ' from Jira, we didn\'t specify expand=changelog. Without that changelog, nothing else is going to' \
      ' work so stopping now.'
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
    @changes.insert 0, create_fake_change_for_creation(@changes)
  end

  def sort_changes!
    @changes.sort! do |a, b|
      # It's common that a resolved will happen at the same time as a status change.
      # Put them in a defined order so tests can be deterministic.
      compare = a.time <=> b.time
      compare = 1 if compare.zero? && a.resolution?
      compare
    end
  end

  def key = @raw['key']

  def type = @raw['fields']['issuetype']['name']

  def summary = @raw['fields']['summary']

  def url
    # Strangely, the URL isn't anywhere in the returned data so we have to fabricate it.
    if @raw['self'] =~ /^(https?:\/\/[^\/]+)\//
      "#{$1}/browse/#{key}"
    else
      ''
    end
  end

  def create_fake_change_for_creation existing_changes
    created_time = @raw['fields']['created']
    first_change = existing_changes.find { |change| change.status? }
    if first_change.nil?
      # There have been no status changes yet so we have to look at the current status
      first_status = @raw['fields']['status']['name']
      first_status_id = @raw['fields']['status']['id'].to_i
    else
      # Otherwise, we look at what the first status had changed away from.
      first_status = first_change.old_value
      first_status_id = first_change.old_value_id
    end
    ChangeItem.new time: created_time, raw: {
      'field' => 'status',
      'to' => first_status_id.to_s,
      'toString' => first_status
    }
  end

  def first_time_in_status *status_names
    @changes.find { |change| change.matches_status status_names }&.time
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
      category = config.project.category_for type: type, status: change.value, issue_id: key
      category_names.include? category
    end
  end

  def first_status_change_after_created
    @changes[1..].find { |change| change.status? }&.time
  end

  def first_time_in_status_category config, *category_names
    @changes.each do |change|
      next unless change.status?

      category = config.category_for type: type, status: change.value, issue_id: key
      return change.time if category_names.include? category
    end
    nil
  end

  def time_created
    DateTime.parse @raw['fields']['created']
  end
end
