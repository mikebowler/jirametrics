# frozen_string_literal: true

require 'time'

class Issue
  attr_reader :changes, :raw, :subtasks, :board
  attr_accessor :parent

  def initialize raw:, board:, timezone_offset: '+00:00'
    @raw = raw
    @timezone_offset = timezone_offset
    @subtasks = []
    @changes = []
    @board = board

    return unless @raw['changelog']

    load_history_into_changes

    # If this is an older pull of data then comments may not be there.
    load_comments_into_changes if @raw['fields']['comment']

    # It might appear that Jira already returns these in order but we've found different
    # versions of Server/Cloud return the changelog in different orders so we sort them.
    sort_changes!

    # It's possible to have a ticket created with certain things already set and therefore
    # not showing up in the change log. Create some artificial entries to capture those.
    @changes = [
      fabricate_change(field_name: 'status'),
      fabricate_change(field_name: 'priority')
    ].compact + @changes
  rescue # rubocop:disable Style/RescueStandardError
    # All we're doing is adding information to the existing exception and letting it propogate up
    raise "Unable to initialize #{raw['key']}"
  end

  def key = @raw['key']

  def type = @raw['fields']['issuetype']['name']

  def type_icon_url = @raw['fields']['issuetype']['iconUrl']

  def summary = @raw['fields']['summary']

  def status = Status.new(raw: @raw['fields']['status'])

  def labels = @raw['fields']['labels'] || []

  def author = @raw['fields']['creator']&.[]('displayName') || ''

  def resolution = @raw['fields']['resolution']&.[]('name')

  def url
    # Strangely, the URL isn't anywhere in the returned data so we have to fabricate it.
    "#{@board.server_url_prefix}/browse/#{key}"
  end

  def key_as_i
    key =~ /-(\d+)$/ ? $1.to_i : 0
  end

  def component_names
    @raw['fields']['components']&.collect { |component| component['name'] } || []
  end

  def first_time_in_status *status_names
    @changes.find { |change| change.current_status_matches(*status_names) }&.time
  end

  def first_time_not_in_status *status_names
    @changes.find { |change| change.status? && status_names.include?(change.value) == false }&.time
  end

  def first_time_in_or_right_of_column column_name
    first_time_in_status(*board.status_ids_in_or_right_of_column(column_name))
  end

  def still_in_or_right_of_column column_name
    still_in_status(*board.status_ids_in_or_right_of_column(column_name))
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
      status_names.include?(change.value) || status_names.include?(change.value_id)
    end
  end

  # If it ever entered one of these categories and it's still there then what was the last time it entered
  def still_in_status_category *category_names
    still_in do |change|
      status = find_status_by_name change.value
      category_names.include?(status.category_name) || category_names.include?(status.category_id)
    end
  end

  def most_recent_status_change
    changes.reverse.find { |change| change.status? }
  end

  # Are we currently in this status? If yes, then return the time of the most recent status change.
  def currently_in_status *status_names
    change = most_recent_status_change
    return false if change.nil?

    change.time if change.current_status_matches(*status_names)
  end

  # Are we currently in this status category? If yes, then return the time of the most recent status change.
  def currently_in_status_category *category_names
    change = most_recent_status_change
    return false if change.nil?

    status = find_status_by_name change.value
    change.time if status && category_names.include?(status.category_name)
  end

  def find_status_by_name name
    status = board.possible_statuses.find_by_name(name)
    return status if status

    raise "Status name #{name.inspect} for issue #{key} not found in #{board.possible_statuses.collect(&:name).inspect}"
  end

  def first_status_change_after_created
    @changes.find { |change| change.status? && change.artificial? == false }&.time
  end

  def first_time_in_status_category *category_names
    @changes.each do |change|
      next unless change.status?

      category = find_status_by_name(change.value).category_name
      return change.time if category_names.include? category
    end
    nil
  end

  def parse_time text
    Time.parse(text).getlocal(@timezone_offset)
  end

  def created
    # This nil check shouldn't be necessary and yet we've seen one case where it was.
    parse_time @raw['fields']['created'] if @raw['fields']['created']
  end

  def updated
    parse_time @raw['fields']['updated']
  end

  def first_resolution
    @changes.find { |change| change.resolution? }&.time
  end

  def last_resolution
    @changes.reverse.find { |change| change.resolution? }&.time
  end

  def assigned_to
    @raw['fields']&.[]('assignee')&.[]('displayName')
  end

  # Many test failures are simply unreadable because the default inspect on this class goes
  # on for pages. Shorten it up.
  def inspect
    "Issue(#{key.inspect})"
  end

  def blocked_on_date? date, end_time:
    (blocked_stalled_by_date date_range: date..date, chart_end_time: end_time)[date].blocked?
  end

  # For any day in the day range...
  # If the issue was blocked at any point in this day, the whole day is blocked.
  # If the issue was active at any point in this day, the whole day is active
  # If the day was stalled for the entire day then it's stalled
  # If there was no activity at all on this day then the last change from the previous day carries over
  def blocked_stalled_by_date date_range:, chart_end_time:, settings: nil
    results = {}
    current_date = nil
    blocked_stalled_changes = blocked_stalled_changes(end_time: chart_end_time, settings: settings)
    blocked_stalled_changes.each do |change|
      current_date = change.time.to_date

      winning_change, _last_change = results[current_date]
      if winning_change.nil? ||
        change.blocked? ||
        (change.active? && (winning_change.active? || winning_change.stalled?)) ||
        (change.stalled? && winning_change.stalled?)

        winning_change = change
      end

      results[current_date] = [winning_change, change]
    end

    last_populated_date = nil
    (results.keys.min..results.keys.max).each do |date|
      if results.key? date
        last_populated_date = date
      else
        _winner, last = results[last_populated_date]
        results[date] = [last, last]
      end
    end
    results = results.transform_values(&:first)

    # The requested date range may span outside the actual changes we find in the changelog
    date_of_first_change = blocked_stalled_changes[0].time.to_date
    date_of_last_change = blocked_stalled_changes[-1].time.to_date
    date_range.each do |date|
      results[date] = blocked_stalled_changes[0] if date < date_of_first_change
      results[date] = blocked_stalled_changes[-1] if date > date_of_last_change
    end

    # To make the code simpler, we've been accumulating data for every date. Now remove anything
    # that isn't in the requested date_range
    results.select! { |date, _value| date_range.include? date }

    results
  end

  def blocked_stalled_changes end_time:, settings: nil
    settings ||= @board.project_config.settings

    blocked_statuses = settings['blocked_statuses']
    stalled_statuses = settings['stalled_statuses']
    unless blocked_statuses.is_a?(Array) && stalled_statuses.is_a?(Array)
      raise "blocked_statuses(#{blocked_statuses.inspect}) and " \
        "stalled_statuses(#{stalled_statuses.inspect}) must both be arrays"
    end

    blocked_link_texts = settings['blocked_link_text']
    stalled_threshold = settings['stalled_threshold_days']

    blocking_issue_keys = []

    result = []
    previous_was_active = false # Must start as false so that the creation will insert an :active
    previous_change_time = created

    blocking_status = nil
    flag = nil

    # This mock change is to force the writing of one last entry at the end of the time range.
    # By doing this, we're able to eliminate a lot of duplicated code in charts.
    mock_change = ChangeItem.new time: end_time, author: '', artificial: true, raw: { 'field' => '' }

    (changes + [mock_change]).each do |change|
      previous_was_active = false if check_for_stalled(
        change_time: change.time,
        previous_change_time: previous_change_time,
        stalled_threshold: stalled_threshold,
        blocking_stalled_changes: result
      )

      if change.flagged?
        flag = change.value
        flag = nil if change.value == ''
      elsif change.status?
        blocking_status = nil
        if blocked_statuses.include?(change.value) || stalled_statuses.include?(change.value)
          blocking_status = change.value
        end
      elsif change.link?
        # Example: "This issue is satisfied by ANON-30465"
        unless /^This issue (?<link_text>.+) (?<issue_key>.+)$/ =~ (change.value || change.old_value)
          puts "Issue(#{key}) Can't parse link text: #{change.value || change.old_value}"
          next
        end

        if blocked_link_texts.include? link_text
          if change.value
            blocking_issue_keys << issue_key
          else
            blocking_issue_keys.delete issue_key
          end
        end
      end

      new_change = BlockedStalledChange.new(
        flagged: flag,
        status: blocking_status,
        status_is_blocking: blocking_status.nil? || blocked_statuses.include?(blocking_status),
        blocking_issue_keys: (blocking_issue_keys.empty? ? nil : blocking_issue_keys.dup),
        time: change.time
      )

      # We don't want to dump two actives in a row as that would just be noise. Unless this is
      # the mock change, which we always want to dump
      result << new_change if !new_change.active? || !previous_was_active || change == mock_change

      previous_was_active = new_change.active?
      previous_change_time = change.time
    end

    if result.size >= 2
      # The existence of the mock entry will mess with the stalled count as it will wake everything
      # back up. This hack will clean up appropriately.
      hack = result.pop
      result << BlockedStalledChange.new(
        flagged: hack.flag,
        status: hack.status,
        status_is_blocking: hack.status_is_blocking,
        blocking_issue_keys: hack.blocking_issue_keys,
        time: hack.time,
        stalled_days: result[-1].stalled_days
      )
    end

    result
  end

  def check_for_stalled change_time:, previous_change_time:, stalled_threshold:, blocking_stalled_changes:
    stalled_threshold_seconds = stalled_threshold * 60 * 60 * 24

    # The most common case will be nothing to split so quick escape.
    return false if (change_time - previous_change_time).to_i < stalled_threshold_seconds

    # If the last identified change was blocked then it doesn't matter now long we've waited, we're still blocked.
    return false if blocking_stalled_changes[-1]&.blocked?

    list = [previous_change_time..change_time]
    all_subtask_activity_times.each do |time|
      matching_range = list.find { |range| time >= range.begin && time <= range.end }
      next unless matching_range

      list.delete matching_range
      list << ((matching_range.begin)..time)
      list << (time..(matching_range.end))
    end

    inserted_stalled = false

    list.sort_by(&:begin).each do |range|
      seconds = (range.end - range.begin).to_i
      next if seconds < stalled_threshold_seconds

      an_hour_later = range.begin + (60 * 60)
      blocking_stalled_changes << BlockedStalledChange.new(stalled_days: seconds / (24 * 60 * 60), time: an_hour_later)
      inserted_stalled = true
    end
    inserted_stalled
  end

  def all_subtask_activity_times
    subtask_activity_times = []
    @subtasks.each do |subtask|
      subtask_activity_times += subtask.changes.collect(&:time)
    end
    subtask_activity_times
  end

  def expedited?
    names = @board&.expedited_priority_names
    return false unless names

    current_priority = raw['fields']['priority']&.[]('name')
    names.include? current_priority
  end

  def expedited_on_date? date
    expedited_start = nil
    expedited_names = @board&.expedited_priority_names

    changes.each do |change|
      next unless change.priority?

      if expedited_names.include? change.value
        expedited_start = change.time.to_date if expedited_start.nil?
      else
        return true if expedited_start && (expedited_start..change.time.to_date).cover?(date)

        expedited_start = nil
      end
    end

    return false if expedited_start.nil?

    expedited_start <= date
  end

  # Return the last time there was any activity on this ticket. Starting from "now" and going backwards
  # Returns nil if there was no activity before that time.
  def last_activity now: Time.now
    result = @changes.reverse.find { |change| change.time <= now }&.time

    # The only condition where this could be nil is if "now" is before creation
    return nil if result.nil?

    @subtasks.each do |subtask|
      subtask_last_activity = subtask.last_activity now: now
      result = subtask_last_activity if subtask_last_activity && subtask_last_activity > result
    end

    result
  end

  def issue_links
    if @issue_links.nil?
      @issue_links = @raw['fields']['issuelinks']&.collect do |issue_link|
        IssueLink.new origin: self, raw: issue_link
      end || []
    end
    @issue_links
  end

  def fix_versions
    if @fix_versions.nil?
      @fix_versions = @raw['fields']['fixVersions']&.collect do |fix_version|
        FixVersion.new fix_version
      end || []
    end
    @fix_versions
  end

  def looks_like_issue_key? key
    !!(key.is_a?(String) && key =~ /^[^-]+-\d+$/)
  end

  def parent_key project_config: @board.project_config
    # Although Atlassian is trying to standardize on one way to determine the parent, today it's a mess.
    # We try a variety of ways to get the parent and hopefully one of them will work. See this link:
    # https://community.developer.atlassian.com/t/deprecation-of-the-epic-link-parent-link-and-other-related-fields-in-rest-apis-and-webhooks/54048

    fields = @raw['fields']

    # At some point in the future, this will be the only way to retrieve the parent so we try this first.
    parent = fields['parent']&.[]('key')

    # The epic field
    parent = fields['epic']&.[]('key') if parent.nil?

    # Otherwise the parent link will be stored in one of the custom fields. We've seen different custom fields
    # used for parent_link vs epic_link so we have to support more than one.
    if parent.nil? && project_config
      custom_field_names = project_config.settings['customfield_parent_links']
      custom_field_names = [custom_field_names] if custom_field_names.is_a? String

      custom_field_names&.each do |field_name|
        parent = fields[field_name]
        next if parent.nil?
        break if looks_like_issue_key? parent

        project_config.file_system.log(
          "Custom field #{field_name.inspect} should point to a parent id but found #{parent.inspect}"
        )
        parent = nil
      end
    end

    parent
  end

  def in_initial_query?
    @raw['exporter'].nil? || @raw['exporter']['in_initial_query']
  end

  # It's artificial if it wasn't downloaded from a Jira instance.
  def artificial?
    @raw['exporter'].nil?
  end

  # Sort by key
  def <=> other
    /(?<project_code1>[^-]+)-(?<id1>.+)/ =~ key
    /(?<project_code2>[^-]+)-(?<id2>.+)/ =~ other.key
    comparison = project_code1 <=> project_code2
    comparison = id1 <=> id2 if comparison.zero?
    comparison
  end

  def dump
    result = +''
    result << "#{key} (#{type}): #{compact_text summary, 200}\n"

    assignee = raw['fields']['assignee']
    result << "  [assignee] #{assignee['name'].inspect} <#{assignee['emailAddress']}>\n" unless assignee.nil?

    raw['fields']['issuelinks'].each do |link|
      result << "  [link] #{link['type']['outward']} #{link['outwardIssue']['key']}\n" if link['outwardIssue']
      result << "  [link] #{link['type']['inward']} #{link['inwardIssue']['key']}\n" if link['inwardIssue']
    end
    changes.each do |change|
      value = change.value
      old_value = change.old_value

      message = "  [change] #{change.time.strftime '%Y-%m-%d %H:%M:%S %z'} [#{change.field}] "
      message << "#{compact_text(old_value).inspect} -> " unless old_value.nil? || old_value.empty?
      message << compact_text(value).inspect
      message << " (#{change.author})"
      message << ' <<artificial entry>>' if change.artificial?
      result << message << "\n"
    end
    result
  end

  private

  def assemble_author raw
    raw['author']&.[]('displayName') || raw['author']&.[]('name') || 'Unknown author'
  end

  def load_history_into_changes
    @raw['changelog']['histories']&.each do |history|
      created = parse_time(history['created'])

      # It should be impossible to not have an author but we've seen it in production
      author = assemble_author history
      history['items']&.each do |item|
        @changes << ChangeItem.new(raw: item, time: created, author: author)
      end
    end
  end

  def load_comments_into_changes
    @raw['fields']['comment']['comments']&.each do |comment|
      raw = {
        'field' => 'comment',
        'to' => comment['id'],
        'toString' =>  comment['body']
      }
      author = assemble_author comment
      created = parse_time(comment['created'])
      @changes << ChangeItem.new(raw: raw, time: created, author: author, artificial: true)
    end
  end

  def compact_text text, max = 60
    return nil if text.nil?

    text = text.gsub(/\s+/, ' ').strip
    text = "#{text[0..max]}..." if text.length > max
    text
  end

  def sort_changes!
    @changes.sort! do |a, b|
      # It's common that a resolved will happen at the same time as a status change.
      # Put them in a defined order so tests can be deterministic.
      compare = a.time <=> b.time
      if compare.zero?
        compare = 1 if a.resolution?
        compare = -1 if b.resolution?
      end
      compare
    end
  end

  def fabricate_change field_name:
    first_status = nil
    first_status_id = nil

    created_time = parse_time @raw['fields']['created']
    first_change = @changes.find { |change| change.field == field_name }
    if first_change.nil?
      # There have been no changes of this type yet so we have to look at the current one
      return nil unless @raw['fields'][field_name]

      first_status = @raw['fields'][field_name]['name']
      first_status_id = @raw['fields'][field_name]['id'].to_i
    else
      # Otherwise, we look at what the first one had changed away from.
      first_status = first_change.old_value
      first_status_id = first_change.old_value_id
    end
    ChangeItem.new time: created_time, artificial: true, author: author, raw: {
      'field' => field_name,
      'to' => first_status_id,
      'toString' => first_status
    }
  end
end
