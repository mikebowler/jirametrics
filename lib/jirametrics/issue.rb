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

    # We only check for this here because if a board isn't passed in then things will fail much
    # later and be hard to find. Let's find out early.
    raise "No board for issue #{key}" if board.nil?

    # There are cases where we create an Issue of fragments like linked issues and those won't have
    # changelogs.
    load_history_into_changes if @raw['changelog']

    # As above with fragments, there may not be a fields section
    return unless @raw['fields']

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

  def priority_name = @raw['fields']['priority']['name']
  def priority_url = @raw['fields']['priority']['iconUrl']

  def summary = @raw['fields']['summary']

  def labels = @raw['fields']['labels'] || []

  def author = @raw['fields']['creator']&.[]('displayName') || ''

  def resolution = @raw['fields']['resolution']&.[]('name')

  def status
    @status = Status.from_raw(@raw['fields']['status']) unless @status
    @status
  end

  def status= status
    @status = status
  end

  def due_date
    text = @raw['fields']['duedate']
    text.nil? ? nil : Date.parse(text)
  end

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
    @changes.find { |change| change.current_status_matches(*status_names) }
  end

  def first_time_not_in_status *status_names
    @changes.find { |change| change.status? && status_names.include?(change.value) == false }
  end

  def first_time_in_or_right_of_column column_name
    first_time_in_status(*board.status_ids_in_or_right_of_column(column_name))
  end

  def first_time_label_added *labels
    @changes.each do |change|
      next unless change.labels?

      change_labels = change.value.split
      return change if change_labels.any? { |l| labels.include?(l) }
    end
    nil
  end

  def still_in_or_right_of_column column_name
    still_in_status(*board.status_ids_in_or_right_of_column(column_name))
  end

  def still_in
    result = nil
    status_changes.each do |change|
      current_status_matched = yield change

      if current_status_matched && result.nil?
        result = change
      elsif !current_status_matched && result
        result = nil
      end
    end
    result
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
    category_ids = find_status_category_ids_by_names category_names

    still_in do |change|
      status = find_or_create_status id: change.value_id, name: change.value
      category_ids.include? status.category.id
    end
  end

  def most_recent_status_change
    # Any issue that we loaded from its own file will always have a status as we artificially insert a status
    # change to represent creation. Issues that were just fragments referenced from a main issue (ie a linked issue)
    # may not have any status changes as we have no idea when it was created. This will be nil in that case
    status_changes.last
  end

  # Are we currently in this status? If yes, then return the most recent status change.
  def currently_in_status *status_names
    change = most_recent_status_change
    return nil if change.nil?

    change if change.current_status_matches(*status_names)
  end

  # Are we currently in this status category? If yes, then return the most recent status change.
  def currently_in_status_category *category_names
    category_ids = find_status_category_ids_by_names category_names

    change = most_recent_status_change
    return nil if change.nil?

    status = find_or_create_status id: change.value_id, name: change.value
    change if status && category_ids.include?(status.category.id)
  end

  def find_or_create_status id:, name:
    status = board.possible_statuses.find_by_id(id)

    unless status
      # Have to pull this list before the call to fabricate or else the warning will incorrectly
      # list this status as one it actually found
      found_statuses = board.possible_statuses.to_s

      status = board.possible_statuses.fabricate_status_for id: id, name: name

      message = +'The history for issue '
      message << key
      message << ' references the status ('
      message << "#{name.inspect}:#{id.inspect}"
      message << ') that can\'t be found. We are guessing that this belongs to the '
      message << status.category.to_s
      message << ' status category but that may be wrong. See https://jirametrics.org/faq/#q1 for more '
      message << 'details on defining statuses.'
      board.project_config.file_system.warning message, more: "The statuses we did find are: #{found_statuses}"
    end

    status
  end

  def first_status_change_after_created
    status_changes.find { |change| change.artificial? == false }
  end

  def first_time_in_status_category *category_names
    category_ids = find_status_category_ids_by_names category_names

    status_changes.each do |change|
      to_status = find_or_create_status(id: change.value_id, name: change.value)
      id = to_status.category.id
      return change if category_ids.include? id
    end
    nil
  end

  def first_time_visible_on_board
    first_time_in_status(*board.visible_columns.collect(&:status_ids).flatten)
  end

  # If this issue will ever be in an active sprint then return the time that it
  # was first added to that sprint, whether or not the sprint was active at that
  # time. Although it seems like an odd thing to calculate, it's a reasonable proxy
  # for 'ready' in cases where the team doesn't have an explicit 'ready' status.
  # You'd be better off with an explicit 'ready' but sometimes that's not an option.
  def first_time_added_to_active_sprint
    data_clazz = Struct.new(:sprint_id, :sprint_start, :sprint_stop, :change)

    matching_changes = []
    all_datas = []

    @changes.each do |change|
      next unless change.sprint?

      added_sprint_ids = change.value_id - change.old_value_id
      added_sprint_ids.each do |id|
        data = data_clazz.new
        data.sprint_id = id
        data.change = change
        sprint_data = raw['fields'][change.field_id].find { |sd| sd['id'].to_i == id }
        data.sprint_start = parse_time(sprint_data['startDate'])
        data.sprint_stop = parse_time(sprint_data['completeDate'])
        all_datas << data
      end

      removed_sprint_ids = change.old_value_id - change.value_id
      removed_sprint_ids.each do |id|
        data = all_datas.find { |d| d.sprint_id == id }

        all_datas.delete(data)

        next if data.sprint_start.nil? || data.sprint_start >= change.time

        matching_changes << data.change
      end
    end

    # There can't be any more removes so whatever is left is a valid option
    # Now all we care about is if the sprint has started.
    all_datas.each do |data|
      matching_changes << data.change if data.sprint_start
    end

    matching_changes.min(&:time)
  end

  def parse_time text
    if text.nil?
      nil
    elsif text.is_a? String
      Time.parse(text).getlocal(@timezone_offset)
    else
      Time.at(text / 1000).getlocal(@timezone_offset)
    end
  end

  def created
    # This nil check shouldn't be necessary and yet we've seen one case where it was.
    parse_time @raw['fields']['created'] if @raw['fields']['created']
  end

  def time_created
    @changes.first
  end

  def updated
    parse_time @raw['fields']['updated']
  end

  def first_resolution
    @changes.find { |change| change.resolution? }
  end

  def last_resolution
    @changes.reverse.find { |change| change.resolution? }
  end

  def assigned_to
    @raw['fields']['assignee']&.[]('displayName')
  end

  def assigned_to_icon_url
    @raw['fields']['assignee']&.[]('avatarUrls')&.[]('16x16')
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
    flagged_means_blocked = !!settings['flagged_means_blocked'] # rubocop:disable Style/DoubleNegation

    blocking_issue_keys = []

    result = []
    previous_was_active = false # Must start as false so that the creation will insert an :active
    previous_change_time = created

    blocking_status = nil
    flag = nil

    # This mock change is to force the writing of one last entry at the end of the time range.
    # By doing this, we're able to eliminate a lot of duplicated code in charts.
    mock_change = ChangeItem.new time: end_time, artificial: true, raw: { 'field' => '' }, author_raw: nil

    (changes + [mock_change]).each do |change|
      previous_was_active = false if check_for_stalled(
        change_time: change.time,
        previous_change_time: previous_change_time,
        stalled_threshold: stalled_threshold,
        blocking_stalled_changes: result
      )

      if change.flagged? && flagged_means_blocked
        flag = change.value
        flag = nil if change.value == ''
      elsif change.status?
        blocking_status = nil
        if blocked_statuses.include?(change.value) || stalled_statuses.include?(change.value)
          blocking_status = change.value
        end
      elsif change.link?
        # Example: "This issue is satisfied by ANON-30465"
        unless /^This (?<_>issue|work item) (?<link_text>.+) (?<issue_key>.+)$/ =~ (change.value || change.old_value)
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

  # return [number of active seconds, total seconds] that this issue had up to the end_time.
  # It does not include data before issue start or after issue end
  def flow_efficiency_numbers end_time:, settings: @board.project_config.settings
    issue_start, issue_stop = @board.cycletime.started_stopped_times(self)
    return [0.0, 0.0] if !issue_start || issue_start > end_time

    value_add_time = 0.0
    end_time = issue_stop if issue_stop && issue_stop < end_time

    active_start = nil
    blocked_stalled_changes(end_time: end_time, settings: settings).each_with_index do |change, index|
      break if change.time > end_time

      if index.zero?
        active_start = change.time if change.active?
        next
      end

      # Already active and we just got another active.
      next if active_start && change.active?

      if change.active?
        active_start = change.time
      elsif active_start && change.time >= issue_start
        # Not active now but we have been. Record the active time.
        change_delta = change.time - [issue_start, active_start].max
        value_add_time += change_delta
        active_start = nil
      end
    end

    if active_start
      change_delta = end_time - [issue_start, active_start].max
      value_add_time += change_delta if change_delta.positive?
    end

    [value_add_time, end_time - issue_start]
  end

  def all_subtask_activity_times
    subtask_activity_times = []
    @subtasks.each do |subtask|
      subtask_activity_times += subtask.changes.collect(&:time)
    end
    subtask_activity_times
  end

  def expedited?
    names = @board.project_config.settings['expedited_priority_names']
    return false unless names

    current_priority = raw['fields']['priority']&.[]('name')
    names.include? current_priority
  end

  def expedited_on_date? date
    expedited_start = nil
    return false unless @board&.project_config

    expedited_names = @board.project_config.settings['expedited_priority_names']

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
    comparison = id1.to_i <=> id2.to_i if comparison.zero?
    comparison
  end

  def discard_changes_before cutoff_time
    rejected_any = false
    @changes.reject! do |change|
      reject = change.status? && change.time <= cutoff_time && change.artificial? == false
      if reject
        (@discarded_changes ||= []) << change
        rejected_any = true
      end
      reject
    end

    (@discarded_change_times ||= []) << cutoff_time if rejected_any
  end

  def dump
    result = +''
    result << "#{key} (#{type}): #{compact_text summary, max: 200}\n"

    assignee = raw['fields']['assignee']
    result << "  [assignee] #{assignee['name'].inspect} <#{assignee['emailAddress']}>\n" unless assignee.nil?

    raw['fields']['issuelinks']&.each do |link|
      result << "  [link] #{link['type']['outward']} #{link['outwardIssue']['key']}\n" if link['outwardIssue']
      result << "  [link] #{link['type']['inward']} #{link['inwardIssue']['key']}\n" if link['inwardIssue']
    end
    history = [] # time, type, detail

    if board.cycletime
      started_at, stopped_at = board.cycletime.started_stopped_times(self)
      history << [started_at, nil, '↓↓↓↓ Started here ↓↓↓↓', true] if started_at
      history << [stopped_at, nil, '↑↑↑↑ Finished here ↑↑↑↑', true] if stopped_at
    else
      result << "  Unable to determine start/end times as board #{board.id} has no cycletime specified\n"
    end

    @discarded_change_times&.each do |time|
      history << [time, nil, '↑↑↑↑ Changes discarded ↑↑↑↑', true]
    end

    (changes + (@discarded_changes || [])).each do |change|
      if change.status?
        value = "#{change.value.inspect}:#{change.value_id.inspect}"
        old_value = change.old_value ? "#{change.old_value.inspect}:#{change.old_value_id.inspect}" : nil
      else
        value = compact_text(change.value).inspect
        old_value = change.old_value ? compact_text(change.old_value).inspect : nil
      end

      message = +''
      message << "#{old_value} -> " unless old_value.nil? || old_value.empty?
      message << value
      if change.artificial?
        message << ' (Artificial entry)' if change.artificial?
      else
        message << " (Author: #{change.author})"
      end
      history << [change.time, change.field, message, change.artificial?]
    end

    result << "  History:\n"
    type_width = history.collect { |_time, type, _detail, _artificial| type&.length || 0 }.max
    history.sort! do |a, b|
      if a[0] == b[0]
        if a[1].nil?
          1
        elsif b[1].nil?
          -1
        else
          a[1] <=> b[1]
        end
      else
        a[0] <=> b[0]
      end
    end
    history.each do |time, type, detail, _artificial|
      if type.nil?
        type = '-' * type_width
      else
        type = (' ' * (type_width - type.length)) << type
      end
      result << "    #{time.strftime '%Y-%m-%d %H:%M:%S %z'} [#{type}] #{detail}\n"
    end

    result
  end

  def done?
    if artificial? || board.cycletime.nil?
      # This was probably loaded as a linked issue, which means we don't know what board it really
      # belonged to. The best we can do is look at the status key
      status.category.done?
    else
      board.cycletime.done? self
    end
  end

  def status_changes
    @changes.select { |change| change.status? }
  end

  def sprints
    sprint_ids = []

    changes.each do |change|
      next unless change.sprint?

      sprint_ids << change.raw['to'].split(/\s*,\s*/).collect { |id| id.to_i }
    end
    sprint_ids.flatten!

    board.sprints.select { |s| sprint_ids.include? s.id }
  end

  def compact_text text, max: 60
    return '' if text.nil?

    if text.is_a? Hash
      # We can't effectively compact it but we can convert it into a string.
      text = @board.project_config.atlassian_document_format.to_html(text)
    else
      text = text.gsub(/\s+/, ' ').strip
      text = "#{text[0...max]}..." if text.length > max
    end
    text
  end

  private

  def load_history_into_changes
    @raw['changelog']['histories']&.each do |history|
      created = parse_time(history['created'])

      history['items']&.each do |item|
        @changes << ChangeItem.new(raw: item, time: created, author_raw: history['author'])
      end
    end
  end

  def load_comments_into_changes
    @raw['fields']['comment']['comments']&.each do |comment|
      raw = comment.merge({
        'field' => 'comment',
        'to' => comment['id'],
        'toString' =>  comment['body']
      })
      created = parse_time(comment['created'])
      @changes << ChangeItem.new(raw: raw, time: created, artificial: true, author_raw: comment['author'])
    end
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

    # There won't be a created timestamp in cases where this was a linked issue
    return unless @raw['fields']['created']

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

    creator = raw['fields']['creator']
    ChangeItem.new time: created_time, artificial: true, author_raw: creator, raw: {
      'field' => field_name,
      'to' => first_status_id,
      'toString' => first_status
    }
  end

  def find_status_category_ids_by_names category_names
    category_names.filter_map do |name|
      list = board.possible_statuses.find_all_categories_by_name name
      raise "No status categories found for name: #{name}" if list.empty?

      list
    end.flatten.collect(&:id)
  end
end
