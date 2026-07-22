# frozen_string_literal: true

require 'time'

class Issue
  attr_reader :changes, :raw, :subtasks, :board, :discarded_changes, :discarded_change_times
  attr_accessor :parent, :github_prs

  def initialize raw:, board:, timezone_offset: '+00:00'
    @raw = raw
    @timezone_offset = timezone_offset
    @subtasks = []
    @changes = []
    @github_prs = []
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
    load_comments_into_changes if raw_fields['comment']

    # It might appear that Jira already returns these in order but we've found different
    # versions of Server/Cloud return the changelog in different orders so we sort them.
    sort_changes!

    # It's possible to have a ticket created with certain things already set and therefore
    # not showing up in the change log. Create some artificial entries to capture those.
    @changes = [
      fabricate_change(field_name: 'status'),
      fabricate_change(field_name: 'priority'),
      fabricate_sprint_change
    ].compact + @changes
  rescue # rubocop:disable Style/RescueStandardError -- deliberately broad: any failure is re-raised with context
    # All we're doing is adding information to the existing exception and letting it propogate up
    raise "Unable to initialize #{raw['key']}"
  end

  def key = @raw['key']

  # 'fields' is the one part of the issue JSON that must always be present -- its absence means the
  # payload is malformed. (Linked-issue fragments legitimately have no fields; that case is guarded in
  # initialize, which returns before any of the fields-based accessors below can run.)
  def raw_fields
    @raw['fields'] || raise("Issue(#{@raw['key']}) has no 'fields'; is this an Issue JSON?")
  end

  def type = raw_fields['issuetype']['name']
  def type_icon_url = raw_fields['issuetype']['iconUrl']

  def priority_name = @raw.dig('fields', 'priority', 'name')
  def priority_url = @raw.dig('fields', 'priority', 'iconUrl')

  def summary = raw_fields['summary']

  def labels = raw_fields['labels'] || []

  def author = raw_fields['creator']&.[]('displayName') || ''

  def resolution = raw_fields['resolution']&.[]('name')

  def status
    @status ||= Status.from_raw(raw_fields['status'])
    @status
  end

  attr_writer :status

  def due_date
    text = raw_fields['duedate']
    text.nil? ? nil : Date.parse(text)
  end

  def url
    # Strangely, the URL isn't anywhere in the returned data so we have to fabricate it.
    "#{@board.server_url_prefix}/browse/#{key}"
  end

  def key_as_i
    /-(?<number>\d+)$/ =~ key ? number.to_i : 0
  end

  def component_names
    raw_fields['components']&.collect { |component| component['name'] } || []
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
      return change if change_labels.intersect?(labels)
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
    visible_status_ids = board.visible_columns.collect(&:status_ids).flatten
    return first_time_in_status(*visible_status_ids) unless board.scrum?

    # On scrum boards an issue is only visible when its status is in a visible column AND it is in an
    # active sprint. Each source below is a moment when the second condition became true while the first
    # already held; the earliest of them is when it first became visible.
    candidates = visible_status_changes_in_active_sprint(visible_status_ids) +
                 sprint_entries_while_in_visible_status(visible_status_ids)
    candidates.min_by(&:time)
  end

  def visible_status_changes_in_active_sprint visible_status_ids
    status_changes.select do |change|
      visible_status_ids.include?(change.value_id) && in_active_sprint_at?(change.time)
    end
  end

  def sprint_entries_while_in_visible_status visible_status_ids
    sprint_entry_events.filter_map do |effective_time, representative_change|
      representative_change if in_visible_status_at?(effective_time, visible_status_ids)
    end
  end

  def reasons_not_visible_on_board
    reasons = []
    reasons << 'Not in an active sprint' if board.scrum? && sprints.none?(&:active?)
    unless board.visible_columns.any? { |c| c.status_ids.include?(status.id) }
      reasons << 'Status is not configured for any visible column on the board'
    end
    reasons
  end

  def visible_on_board?
    reasons_not_visible_on_board.empty?
  end

  # A sprint the issue was added to: its start (all we care about is whether it started) and the change
  # that added it.
  SprintMembership = Data.define(:sprint_id, :sprint_start, :change)

  # Like SprintMembership but also tracks when this issue was added, used while pairing sprint entries
  # and exits in #sprint_entry_events.
  TrackedSprint = Data.define(:sprint_id, :sprint_start, :add_time, :change)

  # If this issue is ever in an active sprint, returns the change where it was first added to that
  # sprint (whether or not the sprint was active at that moment). It's a reasonable proxy for 'ready'
  # when a team has no explicit 'ready' status -- you'd be better off with one, but sometimes that's
  # not an option. Only valid for Scrum boards.
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def first_time_added_to_active_sprint
    # Why are complexity warnings disabled? Bottom line is that we felt the code would be less readable
    # if we split it, so it's remaining as one longer method.

    unless board.scrum?
      raise 'first_time_added_to_active_sprint() can only be used with Scrum boards: ' \
          "issue=#{key}, board=#{board.inspect}"
    end
    matching_changes = []
    memberships = []

    @changes.each do |change|
      next unless change.sprint?

      added_sprint_ids = change.value_id - change.old_value_id
      added_sprint_ids.each do |id|
        sprint_start = find_sprint_start_end(sprint_id: id, change: change).first
        memberships << SprintMembership.new(sprint_id: id, sprint_start:, change:)
      end

      removed_sprint_ids = change.old_value_id - change.value_id
      removed_sprint_ids.each do |id|
        membership = memberships.find { |m| m.sprint_id == id }
        # It's possible for an issue to be created inside a sprint and therefore for
        # that add-to-sprint not show in the history.
        next unless membership

        memberships.delete(membership)
        next unless counts_as_sprint_start? membership
        next if membership.sprint_start >= change.time

        matching_changes << membership.change
      end
    end

    # There can't be any more removes so whatever is left is a valid option
    # Now all we care about is if the sprint has started.
    memberships.each do |membership|
      matching_changes << membership.change if counts_as_sprint_start? membership
    end

    matching_changes.min_by(&:time)
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Being added to a sprint only counts as a "start" if that sprint had actually started and the issue
  # wasn't already done when it did. Joining a sprint you've already finished (e.g. a done issue swept
  # into a later sprint) is bookkeeping on completed work, not the moment work began.
  def counts_as_sprint_start? membership
    return false if membership.sprint_start.nil?

    !in_done_status_at?(membership.sprint_start)
  end

  # Was the issue sitting in a done-category status at the given moment? Keys off the status category
  # (not the status name), so a status merely called "Done" that Jira categorises otherwise won't count.
  def in_done_status_at? time
    last = status_changes.reverse.find { |change| change.time <= time }
    return false unless last

    find_or_create_status(id: last.value_id, name: last.value).category.done?
  end

  def find_sprint_start_end sprint_id:, change:
    # There are two different places that sprint data could be found. In theory all
    # sprints would be found in both places. In practice, sometimes what we need is
    # in one or the other but not both.
    times = sprint_times_from_board(sprint_id) || sprint_times_from_issue(sprint_id, change)

    # If both came up empty then the sprint can't be found anywhere, so we pretend that it never
    # started. Is this guaranteed to be true? No. In theory if all issues were removed from
    # an active sprint then it would also disappear, even though it had started. Nothing we
    # can do to detect that edge-case though.
    times || [nil, nil]
  end

  # First look in the actual sprints json. If any issues are in this sprint then it should be here.
  def sprint_times_from_board sprint_id
    sprint = board.sprints.find { |s| s.id == sprint_id }
    return nil unless sprint
    return [nil, nil] if sprint.future?

    [sprint.start_time, sprint.completed_time]
  end

  # Then look at the sprints inside the issue. Even though the field id may be specified, that custom
  # field may not be present. This happens if it was in that sprint but was then removed, whether or
  # not that sprint had ever started.
  def sprint_times_from_issue sprint_id, change
    sprint_data = raw['fields'][change.field_id]&.find { |sd| sd['id'].to_i == sprint_id }
    return nil unless sprint_data
    return [nil, nil] if sprint_data['state'] == 'future'

    [parse_time(sprint_data['startDate']), parse_time(sprint_data['completeDate'])]
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
    created_text = raw_fields['created']
    parse_time created_text if created_text
  end

  def time_created
    @changes.first
  end

  def updated
    parse_time raw_fields['updated']
  end

  def first_resolution
    @changes.find(&:resolution?)
  end

  def last_resolution
    @changes.reverse.find(&:resolution?)
  end

  def assigned_to
    raw_fields['assignee']&.[]('displayName')
  end

  def assigned_to_icon_url
    raw_fields['assignee']&.[]('avatarUrls')&.[]('16x16')
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
    BlockedStalledByDateBuilder.new(
      blocked_stalled_changes: blocked_stalled_changes(end_time: chart_end_time, settings: settings),
      date_range: date_range
    ).build
  end

  def blocked_stalled_changes end_time:, settings: nil
    settings ||= @board.project_config.settings
    BlockedStalledChangeStreamBuilder.new(
      changes: changes,
      settings: settings,
      created: created,
      key: key,
      subtask_activity_times: all_subtask_activity_times,
      atlassian_document_format: @board.project_config.atlassian_document_format
    ).build(end_time: end_time)
  end

  # return [number of active seconds, total seconds] that this issue had up to the end_time.
  # It does not include data before issue start or after issue end
  def flow_efficiency_numbers end_time:, settings: @board.project_config.settings
    issue_start, issue_stop = started_stopped_times
    return [0.0, 0.0] if !issue_start || issue_start > end_time

    # Nothing after the issue finishes counts, so cap the window before we build the stream.
    end_time = issue_stop if issue_stop && issue_stop < end_time
    FlowEfficiencyCalculator.new(
      blocked_stalled_changes: blocked_stalled_changes(end_time: end_time, settings: settings),
      issue_start: issue_start,
      end_time: end_time
    ).calculate
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
    return false unless @board&.project_config

    expedited_ranges.any? { |range| range.cover?(date) }
  end

  # The date ranges during which this issue sat at an expedited priority. A range that never closes
  # (the issue was never de-prioritised) is endless.
  def expedited_ranges
    expedited_names = @board.project_config.settings['expedited_priority_names']
    ranges = []
    started_on = nil

    changes.each do |change|
      next unless change.priority?

      if expedited_names.include? change.value
        started_on ||= change.time.to_date
      elsif started_on
        ranges << (started_on..change.time.to_date)
        started_on = nil
      end
    end
    ranges << (started_on..) if started_on
    ranges
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
      @issue_links = raw_fields['issuelinks']&.collect do |issue_link|
        IssueLink.new origin: self, raw: issue_link
      end || []
    end
    @issue_links
  end

  def fix_versions
    if @fix_versions.nil?
      @fix_versions = raw_fields['fixVersions']&.collect do |fix_version|
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
    fields = raw_fields

    # The 'parent' field will eventually be the only way; the 'epic' field is the older form. Failing
    # both, the parent link may be stored in a custom field.
    parent = fields['parent']&.[]('key') || fields['epic']&.[]('key')
    parent ||= parent_from_custom_fields(fields, project_config) if project_config
    parent
  end

  def parent_from_custom_fields fields, project_config
    # We've seen different custom fields used for parent_link vs epic_link, so we try each configured
    # one until we find a value that looks like an issue key.
    custom_field_names = project_config.settings['customfield_parent_links']
    custom_field_names = [custom_field_names] if custom_field_names.is_a? String

    custom_field_names&.each do |field_name|
      parent = fields[field_name]
      next if parent.nil?
      return parent if looks_like_issue_key? parent

      project_config.file_system.log(
        "Custom field #{field_name.inspect} should point to a parent id but found #{parent.inspect}"
      )
    end
    nil
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
      next false unless discardable_before? change, cutoff_time

      (@discarded_changes ||= []) << change
      rejected_any = true
    end

    (@discarded_change_times ||= []) << cutoff_time if rejected_any
  end

  def discardable_before? change, cutoff_time
    change.status? && change.time <= cutoff_time && change.artificial? == false
  end

  def dump
    IssuePrinter.new(self).to_s
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

  def started_stopped_times
    board.cycletime.started_stopped_times(self)
  end

  def started_stopped_dates
    board.cycletime.started_stopped_dates(self)
  end

  def status_changes
    @changes.select(&:status?)
  end

  def status_resolution_at_done
    done_time = started_stopped_times.last
    return [nil, nil] if done_time.nil?

    status_change = nil
    resolution = nil

    @changes.each do |change|
      break if change.time > done_time

      status_change = change if change.status?
      resolution = change.value if change.resolution?
    end

    status = status_change ? find_or_create_status(id: status_change.value_id, name: status_change.value) : nil
    [status, resolution]
  end

  def sprints
    sprint_ids = []

    changes.each do |change|
      next unless change.sprint?

      sprint_ids << change.raw['to'].split(/\s*,\s*/).collect(&:to_i)
    end
    sprint_ids.flatten!

    board.sprints.select { |s| sprint_ids.include? s.id }
  end

  def started_sprints
    sprints.reject(&:future?)
  end

  def compact_text text, max: 60
    return '' if text.nil?

    text = @board.project_config.atlassian_document_format.to_text(text) if text.is_a? Hash
    text = text.gsub(/\s+/, ' ').strip
    text = "#{text[0...max]}..." if text.length > max
    text
  end

  private

  # Returns [[effective_time, change_item]] for each moment the issue entered an active sprint.
  # Skips sprints that were removed before they activated.
  def sprint_entry_events
    events = []
    in_sprint = []

    @changes.each do |change|
      next unless change.sprint?

      add_tracked_sprints(in_sprint, change)
      close_tracked_sprints(in_sprint, change, events)
    end

    # Anything still tracked at the end never left, so its entry is the moment it started (or was added).
    in_sprint.each { |tracked| events << sprint_entry_event_for(tracked) }
    events
  end

  # Records each sprint this change newly joined, but only those we know eventually started.
  def add_tracked_sprints in_sprint, change
    (change.value_id - change.old_value_id).each do |sprint_id|
      sprint_start, = find_sprint_start_end(sprint_id: sprint_id, change: change)
      in_sprint << TrackedSprint.new(sprint_id:, sprint_start:, add_time: change.time, change:) if sprint_start
    end
  end

  # Emits an entry for each sprint this change left, unless it was removed before ever activating.
  def close_tracked_sprints in_sprint, change, events
    (change.old_value_id - change.value_id).each do |sprint_id|
      tracked = in_sprint.find { |candidate| candidate.sprint_id == sprint_id }
      next unless tracked

      in_sprint.delete(tracked)
      next if tracked.sprint_start >= change.time # sprint hadn't activated before removal

      events << sprint_entry_event_for(tracked)
    end
  end

  # The moment the issue was effectively in an active sprint - the later of when it was added and when
  # the sprint started - paired with the change that best represents that moment.
  def sprint_entry_event_for tracked
    effective_time = [tracked.add_time, tracked.sprint_start].max
    [effective_time, sprint_change_at(effective_time, tracked.change)]
  end

  def sprint_change_at effective_time, change
    return change if effective_time == change.time

    ChangeItem.new(
      raw: { 'field' => 'Sprint', 'toString' => 'Sprint activated', 'to' => '0', 'from' => nil, 'fromString' => nil },
      author_raw: nil,
      time: effective_time,
      artificial: true
    )
  end

  def in_active_sprint_at? time
    active_ids = []
    @changes.each do |change|
      break if change.time > time
      next unless change.sprint?

      apply_sprint_membership_change(active_ids, change, time)
    end
    active_ids.any?
  end

  # Adds the sprints newly joined by this change (only if they had already started by `time`) and
  # removes the ones it left, mutating active_ids in place.
  def apply_sprint_membership_change active_ids, change, time
    (change.value_id - change.old_value_id).each do |sprint_id|
      sprint_start, = find_sprint_start_end(sprint_id: sprint_id, change: change)
      active_ids << sprint_id if sprint_start && sprint_start <= time
    end
    (change.old_value_id - change.value_id).each { |id| active_ids.delete(id) }
  end

  def in_visible_status_at? time, visible_status_ids
    last = status_changes.reverse.find { |c| c.time <= time }
    last && visible_status_ids.include?(last.value_id)
  end

  def load_history_into_changes
    @raw['changelog']['histories']&.each do |history|
      created = parse_time(history['created'])

      history['items']&.each do |item|
        item = backfill_missing_status_id(item) if item['field'] == 'status' && item['to'].nil?
        @changes << ChangeItem.new(raw: item, time: created, author_raw: history['author'])
      end
    end
  end

  # Jira sometimes reports a status change with a name but no id. Guess the id from the name (when we
  # can) and return a copy of the item with a 'to' filled in, logging what we did.
  def backfill_missing_status_id item
    to_name = item['toString']
    matches = board.possible_statuses.find_all_by_name(to_name)
    guessed_id, id_note = guess_status_id(to_name, matches)
    board.project_config.file_system.warning(
      "Issue #{key} has a status change without a 'to' id " \
      "(from #{item['fromString'].inspect} to #{to_name.inspect}). #{id_note}"
    )
    item.merge('to' => guessed_id)
  end

  # Returns [id_as_string, explanation]. A single name match gives that id; anything else falls back to
  # id 0 because we can't safely disambiguate.
  def guess_status_id to_name, matches
    if matches.length == 1
      [matches.first.id.to_s, "Guessed id #{matches.first.id} from status name."]
    elsif matches.length > 1
      ['0', "Multiple statuses named #{to_name.inspect} exist " \
            "(ids: #{matches.map(&:id).join(', ')}); cannot disambiguate. Using id 0."]
    else
      ['0', "No known status named #{to_name.inspect}. Using id 0."]
    end
  end

  def load_comments_into_changes
    raw_fields['comment']['comments']&.each do |comment|
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
    return unless raw_fields['created']

    created_time = parse_time raw_fields['created']
    first_change = @changes.find { |change| change.field == field_name }
    if first_change.nil?
      # There have been no changes of this type yet so we have to look at the current one
      return nil unless raw_fields[field_name]

      first_status = raw_fields[field_name]['name']
      first_status_id = raw_fields[field_name]['id'].to_i
    else
      # Otherwise, we look at what the first one had changed away from.
      first_status = first_change.old_value
      # old_value_id should never be nil — a status change must have a 'from' id — but Jira has
      # been seen in production omitting the 'from' field entirely. Fall back to 0 so the
      # downstream fabricate/warn path handles it rather than crashing.
      first_status_id = first_change.old_value_id || 0
    end

    creator = raw_fields['creator']
    ChangeItem.new time: created_time, artificial: true, author_raw: creator, raw: {
      'field' => field_name,
      'to' => first_status_id,
      'toString' => first_status
    }
  end

  # Jira never records an issue's *initial* sprint membership as a changelog transition, so an issue
  # created directly inside a sprint (and never moved out) has no Sprint change at all, and one whose
  # first recorded change already lists the sprint in its 'from' looks like it entered at that later
  # moment. Reconstruct that initial membership as an artificial change at creation time, mirroring how
  # we fabricate the initial status and priority. Returns nil when the issue started in no sprints.
  def fabricate_sprint_change
    return unless raw_fields['created']

    first_sprint_change = @changes.find(&:sprint?)
    initial_sprint_ids = first_sprint_change ? first_sprint_change.old_value_id : current_sprint_ids
    return if initial_sprint_ids.empty?

    ChangeItem.new(
      time: parse_time(raw_fields['created']), artificial: true, author_raw: raw_fields['creator'],
      raw: {
        'field' => 'Sprint',
        'fieldId' => first_sprint_change&.field_id || sprint_field_id,
        'to' => initial_sprint_ids.join(', '),
        'toString' => 'Sprint'
      }
    )
  end

  # The Sprint custom field id varies by Jira instance, so we find it by shape: its value is a list of
  # sprint objects, each of which carries a boardId. Returns nil when the issue is in no sprints.
  def sprint_field_id
    field = raw_fields.find do |_field_id, value|
      value.is_a?(Array) && value.first.is_a?(Hash) && value.first.key?('boardId')
    end
    field&.first
  end

  def current_sprint_ids
    field_id = sprint_field_id
    return [] unless field_id

    raw_fields[field_id].filter_map { |sprint| sprint['id']&.to_i }
  end

  def find_status_category_ids_by_names category_names
    category_names.filter_map do |name|
      list = board.possible_statuses.find_all_categories_by_name name
      raise "No status categories found for name: #{name}" if list.empty?

      list
    end.flatten.collect(&:id)
  end
end
